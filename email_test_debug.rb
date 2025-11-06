# Email Testing and Debugging Script for AWS SES
# Run this in Rails console: load 'email_test_debug.rb'

puts "\n" + '=' * 70
puts 'AWS SES SMTP EMAIL TESTING & DEBUGGING SCRIPT'
puts '=' * 70 + "\n"

# Step 1: Check SMTP Configuration
puts '1️⃣  CHECKING SMTP CONFIGURATION...'
puts '-' * 70

smtp_settings = Rails.configuration.action_mailer.smtp_settings
puts "✓ SMTP Address: #{smtp_settings[:address]}"
puts "✓ SMTP Port: #{smtp_settings[:port]}"
puts "✓ SMTP Username: #{smtp_settings[:user_name]}"
puts "✓ SMTP Password: #{smtp_settings[:password] ? '***configured***' : '❌ NOT SET'}"
puts "✓ Authentication: #{smtp_settings[:authentication]}"
puts "✓ STARTTLS: #{smtp_settings[:enable_starttls_auto]}"

# Step 2: Check ActionMailer Configuration
puts "\n2️⃣  CHECKING ACTION MAILER CONFIGURATION..."
puts '-' * 70

puts "✓ Delivery Method: #{Rails.configuration.action_mailer.delivery_method}"
puts "✓ Perform Deliveries: #{Rails.configuration.action_mailer.perform_deliveries}"
puts "✓ Raise Delivery Errors: #{Rails.configuration.action_mailer.raise_delivery_errors}"

default_url = begin
  Rails.configuration.action_mailer.default_url_options
rescue StandardError
  nil
end
if default_url
  puts "✓ Default URL Options: #{default_url.inspect}"
else
  puts '⚠️  Default URL Options: NOT SET (may cause issues with email links)'
end

default_from = begin
  Rails.configuration.action_mailer.default_options[:from]
rescue StandardError
  nil
end
puts "✓ Default FROM Email: #{default_from || '⚠️  NOT SET'}"

# Step 3: Test SMTP Connection
puts "\n3️⃣  TESTING SMTP CONNECTION..."
puts '-' * 70

begin
  require 'net/smtp'

  smtp = Net::SMTP.new(smtp_settings[:address], smtp_settings[:port])
  smtp.enable_starttls_auto if smtp_settings[:enable_starttls_auto]

  smtp.start(
    'localhost',
    smtp_settings[:user_name],
    smtp_settings[:password],
    smtp_settings[:authentication]
  ) do |_smtp_obj|
    puts '✅ SMTP connection successful!'
    puts "   Server: #{smtp_settings[:address]}:#{smtp_settings[:port]}"
  end
rescue StandardError => e
  puts '❌ SMTP CONNECTION FAILED!'
  puts "   Error: #{e.class}"
  puts "   Message: #{e.message}"
  puts "\n   Possible causes:"
  puts '   - Incorrect SMTP username or password'
  puts "   - Firewall blocking port #{smtp_settings[:port]}"
  puts '   - Wrong SMTP endpoint for your region'
end

# Step 4: Send Test Email
puts "\n4️⃣  SENDING TEST EMAIL..."
puts '-' * 70

test_from = 'm0inahmedquintype@gmail.com'
test_to = 'm0inahmedquintype@gmail.com'

puts "FROM: #{test_from}"
puts "TO: #{test_to}"
puts "Subject: AWS SES Test Email - #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
puts "\nAttempting to send..."

begin
  mail = ActionMailer::Base.mail(
    from: test_from,
    to: test_to,
    subject: "AWS SES Test Email - #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}",
    body: <<~BODY
      Hello!

      This is a test email sent from your Rails application using AWS SES SMTP.

      Configuration Details:
      - SMTP Server: #{smtp_settings[:address]}
      - Port: #{smtp_settings[:port]}
      - Sent at: #{Time.now}
      - Environment: #{Rails.env}

      If you're reading this, your email configuration is working correctly! 🎉

      Best regards,
      Your Rails App
    BODY
  )

  mail.deliver_now

  puts "\n✅ EMAIL SENT SUCCESSFULLY!"
  puts "   Message ID: #{mail.message_id}"
  puts "\n📧 Check your inbox at: #{test_to}"
  puts '   (Check spam/junk folder if not in inbox)'
  puts "\n   Note: Delivery may take 1-5 minutes"
rescue StandardError => e
  puts "\n❌ EMAIL SENDING FAILED!"
  puts "   Error: #{e.class}"
  puts "   Message: #{e.message}"
  puts "\n   Full backtrace:"
  puts e.backtrace.first(10).join("\n   ")

  puts "\n   Common issues:"
  puts '   1. Email not verified in AWS SES'
  puts '   2. Incorrect FROM email address'
  puts '   3. AWS SES account in sandbox mode (can only send to verified emails)'
  puts '   4. SMTP credentials incorrect'
end

# Step 5: Check AWS SES Sandbox Status
puts "\n5️⃣  AWS SES ACCOUNT STATUS..."
puts '-' * 70
puts '⚠️  Your AWS SES account is likely in SANDBOX mode.'
puts "\nIn sandbox mode:"
puts '  ✅ You CAN send to: m0inahmedquintype@gmail.com (verified)'
puts '  ❌ You CANNOT send to: unverified email addresses'
puts "\n  To send to any email address, request production access:"
puts '  → AWS Console → SES → Account dashboard → Request production access'

# Step 6: Next Steps
puts "\n6️⃣  NEXT STEPS..."
puts '-' * 70
puts '1. Check the email output above for any errors'
puts "2. If successful, check your Gmail inbox: #{test_to}"
puts '3. Check spam/junk folder if not in inbox'
puts '4. If using Devise, test with:'
puts "   user = Spree::User.find_by(email: 'm0inahmedquintype@gmail.com')"
puts '   user.send_confirmation_instructions'
puts "\n5. Check Rails logs for detailed SMTP communication:"
puts '   tail -f log/development.log'

puts "\n" + '=' * 70
puts 'TESTING COMPLETE'
puts '=' * 70 + "\n"
