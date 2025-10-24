# frozen_string_literal: true

class SmsService
  class << self
    # Send verification code via SMS
    # In development: logs to console
    # In production: replace with real SMS service (Twilio, AWS SNS, etc.)
    def send_verification(phone_number, verification_code)
      if Rails.env.production?
        # TODO: Implement real SMS service
        # Example with Twilio:
        # client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
        # client.messages.create(
        #   from: ENV['TWILIO_PHONE_NUMBER'],
        #   to: phone_number,
        #   body: "Your verification code is: #{verification_code}"
        # )

        Rails.logger.warn('SMS Service not configured for production!')
        false
      else
        # Development/Test: Log to console
        log_mock_sms(phone_number, verification_code)
        true
      end
    end

    private

    def log_mock_sms(phone_number, verification_code)
      message = <<~SMS

        ╔═══════════════════════════════════════════════════════╗
        ║              MOCK SMS SERVICE (Development)           ║
        ╠═══════════════════════════════════════════════════════╣
        ║ To: #{phone_number.ljust(47)}║
        ║                                                       ║
        ║ Message:                                              ║
        ║ Your verification code is: #{verification_code[0..5].ljust(30)}║
        ║                                                       ║
        ║ This code will expire in 10 minutes.                 ║
        ╚═══════════════════════════════════════════════════════╝

      SMS

      Rails.logger.info(message)
      puts message # Also print to console
    end
  end
end
