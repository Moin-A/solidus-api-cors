# AWS SES SMTP Setup Guide

This guide walks you through setting up Amazon Simple Email Service (SES) SMTP for sending emails in your Rails application.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Step 1: Create SMTP Credentials in AWS](#step-1-create-smtp-credentials-in-aws)
- [Step 2: Verify Email Address or Domain](#step-2-verify-email-address-or-domain)
- [Step 3: Configure Rails Application](#step-3-configure-rails-application)
- [Step 4: Test Email Sending](#step-4-test-email-sending)
- [Step 5: Request Production Access](#step-5-request-production-access)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)

---

## Prerequisites

- AWS Account with root or IAM access
- Access to AWS Console
- Rails application with Devise (or similar email functionality)

---

## Step 1: Create SMTP Credentials in AWS

### 1.1 Navigate to AWS SES Console

1. Log in to [AWS Console](https://console.aws.amazon.com/)
2. In the search bar, type **"SES"** and select **"Amazon Simple Email Service"**
3. Select your preferred region (e.g., Europe - Stockholm: `eu-north-1`)

### 1.2 Access SMTP Settings

1. In the SES Console, open the **side navigation menu**
2. Click on **"SMTP settings"**
3. Note down the SMTP endpoint for your region:
   ```
   email-smtp.eu-north-1.amazonaws.com
   ```

### 1.3 Create SMTP Credentials

1. Click **"Create SMTP credentials"** button
2. You'll be redirected to IAM console
3. Accept the auto-generated user name (or customize it):
   ```
   ses-smtp-user.YYYYMMDD-HHMMSS
   ```
4. Review the permissions policy (it should allow `ses:SendRawEmail`)
5. Click **"Create user"**

### 1.4 Save Your Credentials

⚠️ **IMPORTANT**: This is the **ONLY time** you can view these credentials!

1. Click **"Show"** to reveal the SMTP password
2. Save the following information:
   - **SMTP Username**: e.g., `AKIAVO3V6QXM4FFZR5UY`
   - **SMTP Password**: e.g., `BP9URS+oSyJUNF0YfrxC8MW+vFCr+2WUxACg23/IJU4w`
3. Click **"Download .csv file"** for backup

### SMTP Configuration Details

```
SMTP Endpoint: email-smtp.<region>.amazonaws.com
SMTP Port: 587 (STARTTLS) or 465 (TLS Wrapper)
TLS: Required
Authentication: LOGIN
```

---

## Step 2: Verify Email Address or Domain

Before sending emails, you must verify your sending identity (email address or domain).

### Option A: Verify Individual Email (Recommended for Testing)

1. In SES Console, navigate to **"Configuration" → "Verified identities"**
2. Click **"Create identity"**
3. Select **"Email address"**
4. Enter your sending email address (e.g., `noreply@yourdomain.com`)
5. Click **"Create identity"**
6. Check your email inbox and click the verification link
7. Status should change to **"Verified"** (refresh page if needed)

### Option B: Verify Domain (Recommended for Production)

1. In SES Console, navigate to **"Configuration" → "Verified identities"**
2. Click **"Create identity"**
3. Select **"Domain"**
4. Enter your domain name (e.g., `yourdomain.com`)
5. Configure these settings:
   - ✅ Enable **DKIM signatures**
   - ✅ Enable **Easy DKIM**
   - Choose DKIM key length: **2048-bit** (recommended)
6. Click **"Create identity"**
7. AWS will provide DNS records (CNAME records)
8. Add these DNS records to your domain's DNS settings:
   - 3 DKIM CNAME records
   - 1 DMARC TXT record (optional but recommended)
   - 1 SPF TXT record (optional but recommended)
9. Wait for DNS propagation (can take up to 72 hours, usually < 24 hours)
10. Status should change to **"Verified"**

### Example DNS Records

```
# DKIM Records (provided by AWS)
<random>._domainkey.yourdomain.com CNAME <random>.dkim.amazonses.com
<random>._domainkey.yourdomain.com CNAME <random>.dkim.amazonses.com
<random>._domainkey.yourdomain.com CNAME <random>.dkim.amazonses.com

# SPF Record (add to existing or create new)
yourdomain.com TXT "v=spf1 include:amazonses.com ~all"

# DMARC Record
_dmarc.yourdomain.com TXT "v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com"
```

---

## Step 3: Configure Rails Application

### 3.1 Set Environment Variables

Add to your environment variables (`.env` file or system environment):

```bash
# AWS SES SMTP Credentials
AWS_SES_SMTP_USERNAME=AKIAVO3V6QXM4FFZR5UY
AWS_SES_SMTP_PASSWORD=BP9URS+oSyJUNF0YfrxC8MW+vFCr+2WUxACg23/IJU4w
AWS_SES_SMTP_ADDRESS=email-smtp.eu-north-1.amazonaws.com
AWS_SES_REGION=eu-north-1

# Email Settings
DEFAULT_FROM_EMAIL=noreply@yourdomain.com
```

**For development with dotenv:**
```bash
# Install gem
bundle add dotenv-rails

# Create .env file (add to .gitignore!)
echo ".env" >> .gitignore
```

**For production (Heroku example):**
```bash
heroku config:set AWS_SES_SMTP_USERNAME=AKIAVO3V6QXM4FFZR5UY
heroku config:set AWS_SES_SMTP_PASSWORD=BP9URS+oSyJUNF0YfrxC8MW+vFCr+2WUxACg23/IJU4w
heroku config:set AWS_SES_SMTP_ADDRESS=email-smtp.eu-north-1.amazonaws.com
heroku config:set DEFAULT_FROM_EMAIL=noreply@yourdomain.com
```

### 3.2 Update Production Configuration

Edit `config/environments/production.rb`:

```ruby
Rails.application.configure do
  # ... other configurations ...

  # Action Mailer Configuration for AWS SES
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  
  config.action_mailer.smtp_settings = {
    address:              ENV['AWS_SES_SMTP_ADDRESS'] || 'email-smtp.eu-north-1.amazonaws.com',
    port:                 587,
    user_name:            ENV['AWS_SES_SMTP_USERNAME'],
    password:             ENV['AWS_SES_SMTP_PASSWORD'],
    authentication:       :login,
    enable_starttls_auto: true
  }

  # Set default URL for action mailer (adjust for your domain)
  config.action_mailer.default_url_options = {
    host: ENV['APP_HOST'] || 'yourdomain.com',
    protocol: 'https'
  }

  # Set default from email
  config.action_mailer.default_options = {
    from: ENV['DEFAULT_FROM_EMAIL'] || 'noreply@yourdomain.com'
  }
end
```

### 3.3 Update Development Configuration (Optional)

For testing in development, edit `config/environments/development.rb`:

```ruby
Rails.application.configure do
  # ... other configurations ...

  # For development, you can use the same SES settings
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  
  config.action_mailer.smtp_settings = {
    address:              ENV['AWS_SES_SMTP_ADDRESS'],
    port:                 587,
    user_name:            ENV['AWS_SES_SMTP_USERNAME'],
    password:             ENV['AWS_SES_SMTP_PASSWORD'],
    authentication:       :login,
    enable_starttls_auto: true
  }

  config.action_mailer.default_url_options = {
    host: 'localhost',
    port: 3000
  }

  config.action_mailer.default_options = {
    from: ENV['DEFAULT_FROM_EMAIL']
  }
end
```

### 3.4 Configure Devise (If Using)

If you're using Devise for authentication, update `config/initializers/devise.rb`:

```ruby
Devise.setup do |config|
  # Set sender email
  config.mailer_sender = ENV['DEFAULT_FROM_EMAIL'] || 'noreply@yourdomain.com'
  
  # ... other configurations ...
end
```

---

## Step 4: Test Email Sending

### 4.1 Rails Console Test

```ruby
# Start Rails console
rails console

# Send a test email
ActionMailer::Base.mail(
  from: ENV['DEFAULT_FROM_EMAIL'],
  to: 'your-verified-email@example.com',
  subject: 'Test Email from Rails',
  body: 'This is a test email sent via AWS SES SMTP.'
).deliver_now

# Check for errors
# If successful, you should see SMTP connection logs
```

### 4.2 Test Your Verification Controller

```ruby
# In Rails console
user = Spree::User.find_by(email: 'test@example.com')
user.send_confirmation_instructions
```

### 4.3 Check AWS SES Sending Statistics

1. Go to AWS SES Console
2. Navigate to **"Account dashboard"**
3. View **"Sending statistics"** to see:
   - Emails sent
   - Delivery rate
   - Bounce rate
   - Complaint rate

---

## Step 5: Request Production Access

### Understanding Sandbox Mode

By default, AWS SES accounts are in **Sandbox mode** with limitations:
- ✅ Can send TO: Verified email addresses only
- ❌ Cannot send TO: Unverified email addresses
- 📊 Sending limit: 200 emails/day
- ⏱️ Rate limit: 1 email/second

### Move to Production

1. Go to AWS SES Console → **"Account dashboard"**
2. Look for **"Production access"** section
3. Click **"Request production access"**
4. Fill out the request form:
   - **Mail type**: Select your use case (e.g., "Transactional")
   - **Website URL**: Your application URL
   - **Use case description**: Explain what emails you'll send (be specific)
     ```
     Example: "We send transactional emails for user registration, 
     password resets, order confirmations, and shipping notifications 
     for our e-commerce platform at yourdomain.com"
     ```
   - **Compliance**: Explain how you handle bounces and complaints
     ```
     Example: "We automatically process bounce and complaint notifications 
     via SNS. Users can unsubscribe from marketing emails, and we maintain 
     a suppression list."
     ```
   - **Preferred contact language**: Select your language
5. Click **"Submit request"**
6. AWS typically reviews within 24 hours

### After Production Access is Granted

You can now:
- ✅ Send to ANY email address
- 📈 Higher sending limits (starts at 50,000 emails/day)
- ⚡ Rate limit: 14 emails/second (and higher with increases)

---

## Troubleshooting

### Common Issues

#### 1. "Email address not verified"
**Error**: `MessageRejected: Email address is not verified`

**Solution**: Verify your FROM email address in SES Console → Verified identities

#### 2. "Daily sending quota exceeded"
**Error**: `Throttling: Maximum sending rate exceeded`

**Solution**: 
- Request production access (see Step 5)
- Monitor your sending statistics
- Implement rate limiting in your application

#### 3. SMTP Authentication Failed
**Error**: `535 Authentication Credentials Invalid`

**Solution**:
- Double-check your SMTP username and password
- Ensure you're using SMTP credentials (not AWS access keys)
- Verify environment variables are loaded correctly

#### 4. Connection Timeout
**Error**: `Connection timeout`

**Solution**:
- Check your firewall allows outbound connections on port 587
- Verify SMTP endpoint matches your region
- Ensure `enable_starttls_auto: true` is set

#### 5. Emails Going to Spam

**Solution**:
- Verify your domain (not just email)
- Set up SPF, DKIM, and DMARC records
- Use a professional FROM address (not no-reply@gmail.com)
- Include proper email headers and valid unsubscribe links
- Maintain low bounce and complaint rates

### Debug Email Delivery

```ruby
# Enable verbose logging in development
# config/environments/development.rb
config.action_mailer.logger = Logger.new(STDOUT)
config.log_level = :debug
```

### Check SES Bounce and Complaint Rates

1. Go to SES Console → **"Reputation metrics"**
2. Monitor:
   - Bounce rate (should be < 5%)
   - Complaint rate (should be < 0.1%)
3. High rates can lead to account suspension

---

## Security Best Practices

### 1. Never Commit Credentials
```bash
# Always add to .gitignore
echo ".env" >> .gitignore
echo ".env.local" >> .gitignore
echo ".env.*.local" >> .gitignore
```

### 2. Use Environment Variables
- Use `dotenv-rails` for development
- Use secure environment variable storage in production (Heroku Config Vars, AWS Secrets Manager, etc.)

### 3. Rotate Credentials Regularly
- Create new SMTP credentials every 90 days
- Delete old credentials after rotation

### 4. Monitor Sending Activity
- Set up CloudWatch alarms for unusual activity
- Review AWS SES sending statistics regularly

### 5. Implement Rate Limiting
```ruby
# Example: Limit emails per user per hour
class EmailRateLimiter
  def self.can_send?(user)
    key = "email_rate_limit:#{user.id}"
    count = Rails.cache.read(key) || 0
    
    if count >= 10 # Max 10 emails per hour
      false
    else
      Rails.cache.write(key, count + 1, expires_in: 1.hour)
      true
    end
  end
end
```

### 6. Set Up SNS Notifications (Advanced)
Configure SNS to handle bounces and complaints automatically:
1. Go to SES Console → Configuration sets
2. Create a configuration set
3. Add SNS destination for bounce and complaint events
4. Create Lambda function or webhook to process notifications

---

## Additional Resources

- [AWS SES Developer Guide](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/)
- [AWS SES SMTP Interface](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/send-email-smtp.html)
- [Rails Action Mailer Guide](https://guides.rubyonrails.org/action_mailer_basics.html)
- [AWS SES Pricing](https://aws.amazon.com/ses/pricing/)

---

## Summary of Configuration

| Setting | Value |
|---------|-------|
| SMTP Host | `email-smtp.<region>.amazonaws.com` |
| SMTP Port | `587` (STARTTLS) or `465` (TLS) |
| Authentication | LOGIN |
| TLS | Required |
| Region | `eu-north-1` (or your selected region) |
| Sandbox Limit | 200 emails/day |
| Production Limit | 50,000+ emails/day |

---

## Current Setup (Your Application)

✅ **SMTP Credentials Created**
- User: `ses-smtp-user.20251017-152733`
- Region: Europe (Stockholm) - `eu-north-1`

✅ **Verification Controller Ready**
- Location: `app/controllers/api/verification_controller.rb`
- Uses Devise confirmation instructions

⏳ **Next Steps**
1. Verify your sending email address/domain
2. Update environment variables with SMTP credentials
3. Test email sending
4. Request production access (when ready)

---

**Last Updated**: October 17, 2025  
**AWS Region**: eu-north-1 (Europe - Stockholm)

