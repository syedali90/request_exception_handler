# The mixin that provides the +request_exception+
# by default included into +ActionController::Base+
module RequestExceptionHandler

  THREAD_LOCAL_NAME = :_request_exception
  
  @@parse_request_parameters_exception_handler = lambda do |request, exception|
    Thread.current[THREAD_LOCAL_NAME] = exception
    request_body = request.respond_to?(:body) ? request.body : request.raw_post

    logger = RequestExceptionHandler.logger
    if logger.info?
      content_log = request_body
      if request_body.is_a?(StringIO)
        pos = request_body.pos
        content_log = request_body.read
      end
      logger.info "#{exception.class.name} occurred while parsing request parameters." +
                  "\nContents:\n#{content_log}\n"
      request_body.pos = pos if pos
    end
              
    content_type = if request.respond_to?(:content_type_with_parameters)
      request.send :content_type_with_parameters # AbstractRequest
    else # rack request
      request.respond_to?(:content_mime_type) ? request.content_mime_type : request.content_type
    end
    puts "REXML::ParseError Request"
    puts request_body.read
    { "body" => request_body, "content_type" => content_type, "content_length" => request.content_length }
  end
  
  begin
    mattr_accessor :parse_request_parameters_exception_handler
  rescue NoMethodError => e
    require('active_support/core_ext/module/attribute_accessors') && retry
    raise e
  end

  # Resets the current +request_exception+ (to nil).
  def self.reset_request_exception
    Thread.current[THREAD_LOCAL_NAME] = nil
  end

  # Retrieves the Rails logger.
  def self.logger
    defined?(Rails.logger) ? Rails.logger : 
      defined?(RAILS_DEFAULT_LOGGER) ? RAILS_DEFAULT_LOGGER : 
        Logger.new($stderr)
  end
  
  def self.included(base)
    base.prepend_before_filter :check_request_exception
  end

  # Checks and raises a +request_exception+ (gets prepended as a before filter).
  def check_request_exception
    e = request_exception
    raise e if e && e.is_a?(Exception)
  end

  # Retrieves and keeps track of the current request exception if any.
  def request_exception
    return @_request_exception if defined? @_request_exception
    @_request_exception = Thread.current[THREAD_LOCAL_NAME]
    RequestExceptionHandler.reset_request_exception
    @_request_exception
  end

end

require 'action_controller/base'
ActionController::Base.send :include, RequestExceptionHandler

# NOTE: Rails monkey patching follows :

if defined? ActionDispatch::ParamsParser # Rails 3.x

  ActionDispatch::ParamsParser.class_eval do

    def parse_formatted_parameters_with_exception_handler(env)
      begin
        out = parse_formatted_parameters_without_exception_handler(env)
        RequestExceptionHandler.reset_request_exception # make sure it's nil
        out
      rescue Exception => e # YAML, XML or Ruby code block errors
        handler = RequestExceptionHandler.parse_request_parameters_exception_handler
        handler ? handler.call(ActionDispatch::Request.new(env), e) : raise
      end
    end

    alias_method_chain :parse_formatted_parameters, :exception_handler

  end

elsif defined? ActionController::ParamsParser # Rails 2.3.x

  ActionController::ParamsParser.class_eval do

    def parse_formatted_parameters_with_exception_handler(env)
      begin
        out = parse_formatted_parameters_without_exception_handler(env)
        RequestExceptionHandler.reset_request_exception # make sure it's nil
        out
      rescue Exception => e # YAML, XML or Ruby code block errors
        handler = RequestExceptionHandler.parse_request_parameters_exception_handler
        handler ? handler.call(ActionController::Request.new(env), e) : raise
      end
    end

    alias_method_chain :parse_formatted_parameters, :exception_handler

  end

else # old-style Rails < 2.3

  ActionController::AbstractRequest.class_eval do

    def parse_formatted_request_parameters_with_exception_handler
      begin
        out = parse_formatted_request_parameters_without_exception_handler
        RequestExceptionHandler.reset_request_exception # make sure it's nil
        out
      rescue Exception => e # YAML, XML or Ruby code block errors
        handler = RequestExceptionHandler.parse_request_parameters_exception_handler
        handler ? handler.call(self, e) : raise
      end
    end

    alias_method_chain :parse_formatted_request_parameters, :exception_handler

  end

end
