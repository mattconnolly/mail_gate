module MailGate
  # MailGate class restricts email delivery to non-whitelisted emails.
  #
  # Each element within the whitelist needs to be a Regex object.
  #
  # To use MailGate within a Rails project, configure a specific environment
  # file or global configuration using the mail_gate delivery method:
  #
  #   config.action_mailer.delivery_method = :mail_gate
  #   config.action_mailer.mail_gate_settings = {
  #     :whitelist => /evil.com|allowed@site.com/
  #   }
  #
  # If you aren't using MailGate within a Rails application, you can still
  # configure Mail to use it as it's default delivery_method.
  #
  #   Mail.defaults do
  #     delivery_method MailGate::Filter, :whitelist => /application.com/
  #   end
  #
  class Filter
    attr_accessor :settings

    # The Regexp to compare emails against.
    attr_accessor :whitelist

    def initialize(settings = {})
      self.settings = settings
      @whitelist = Regexp.new(settings.fetch(:whitelist, /.*/))
      delivery_method = settings.fetch(:delivery_method, :test)
      delivery_settings = settings.fetch(:delivery_settings, {})
      @delivery_method = Mail::Configuration.instance.lookup_delivery_method(delivery_method).new(delivery_settings)
    end

    # Public: Filter out recipients who may match the whitelist regex.
    # If no emails are present after being filtered, don't deliver the email. 
    #
    # mail - Mail object containing headers and body.
    #
    # Returns instance of Mail::Message.
    def deliver!(mail)
      original_emails = email_list(mail)

      %w{ to cc bcc }.each do |field|
        mail.send(:"#{field}=", filter_emails(mail.send(field)))
      end

      rejected_emails = original_emails - email_list(mail)

      if settings[:append_emails] != false && rejected_emails.any?
        mail.body = "#{mail.body}\n\nExtracted Recipients: #{rejected_emails.join(', ')}"
      end

      if settings[:subject_prefix]
        mail.subject = settings[:subject_prefix] + mail.subject
      end

      if rejected_emails.any? && defined?(ActionMailer)
        ActionMailer::Base.logger.info { "MailGate: suppressing mail to #{rejected_emails.join(', ')}" }
      end

      @delivery_method.deliver!(mail) unless mail.to.blank?

      mail
    end

    private

    # Private: Filter out any emails that match the whitelist regex.
    #
    # emails - List of emails to filter through.
    #
    # Examples
    #
    #   Given [/github.com/] being the whitelist.
    #
    #   filter_emails('me@garrettbjerkhoel.com')
    #   # => nil
    #
    #   filter_emails(['me@garrettbjerkhoel.com', 'evil@hacking.com'])
    #   # => 'garrett@github.com'
    #
    #   filter_emails(['matt@github.com', 'garrett@github.com'])
    #   # => ['matt@github.com', 'garrett@github.com']
    #
    # Returns array of emails if the list is greater than one, if only one item
    # return just that single email, if empty, return nil to reset the field.
    def filter_emails(emails)
      return if emails.blank?

      email_list = Array(emails).select do |recipient|
        recipient.to_s =~ @whitelist
      end

      email_list.length > 1 ? email_list : email_list.shift
    end

    # Private: Get all unique emails across all headers that the email may contain.
    #
    # mail - Mail object
    #
    # Return Array of email addresses.
    def email_list(mail)
      [mail.to, mail.bcc, mail.cc].flatten.uniq.compact
    end
  end
end
