# frozen_string_literal: true

module UserVerification
  extend ActiveSupport::Concern

  included do
    # Validations
    validates :phone_number,
              format: { with: /\A\+?[1-9]\d{1,14}\z/, message: 'must be a valid phone number' },
              allow_blank: true

    # Callbacks
    before_create :generate_phone_verification_token
  end

  # Generate secure random token for phone verification
  def generate_phone_verification_token
    self.phone_verification_token = SecureRandom.urlsafe_base64(6) # 6-digit code
  end

  # Send phone verification (mock for now)
  def send_phone_verification
    generate_phone_verification_token unless phone_verification_token
    self.phone_verification_sent_at = Time.current
    save!

    # Send verification SMS (mock service)
    SmsService.send_verification(phone_number, phone_verification_token)
  end

  # Verify phone with token
  def verify_phone!(token)
    if phone_verification_token == token
      update!(phone_verified: true, phone_verification_token: nil)
      true
    else
      false
    end
  end

  # Check if user is fully verified (either/or logic)
  # - If both email and phone provided → verify only email
  # - If only phone provided → verify only phone
  # - If only email provided → verify only email
  def fully_verified?
    if email.present? && phone_number.present?
      # Both provided - only check email confirmation
      confirmed?
    elsif phone_number.present?
      # Only phone - check phone verification
      phone_verified?
    else
      # Only email - check email confirmation
      confirmed?
    end
  end

  # Check if phone verification can be resent (prevent spam)
  def can_resend_phone_verification?
    phone_verification_sent_at.nil? || phone_verification_sent_at < 2.minutes.ago
  end
end
