# User Verification System - Devise Confirmable + SMS

## Overview

Hybrid verification system using:
- **Devise confirmable** for email verification (battle-tested, built-in)
- **Custom SMS verification** for phone verification
- **Either/or verification logic:**
  - If both email AND phone provided → verify only email
  - If only phone provided → verify only phone
  - If only email provided → verify only email

## Features

- Email confirmation via Devise confirmable (automatic token generation, expiry, resend)
- SMS/Phone verification with OTP codes (custom implementation)
- **Either/or verification:** Only one method required (email takes priority if both provided)
- Rate limiting on phone verification resend (2 minutes)
- Mock SMS service for development
- Devise's production-ready email templates

---

## Either/Or Verification Logic

The system uses a smart either/or approach to avoid forcing users to verify both methods:

| User Provides | Verification Required | Method Used |
|--------------|----------------------|-------------|
| Email + Phone | **Email only** | Devise confirmable (email takes priority) |
| Email only | **Email only** | Devise confirmable |
| Phone only | **Phone only** | Custom SMS verification |

**Why this approach?**
- Simpler user experience (one verification step instead of two)
- Email verification is more reliable and established
- Phone verification still available for email-less registrations
- Reduces friction in signup flow

**Implementation:**
- During registration, system checks what contact info was provided
- Sends verification for the appropriate method
- `fully_verified?` method checks based on what user provided
- Login blocked until the required verification is complete

---

## Registration Flow

### 1. User Registers

**Endpoint:** `POST /api/register`

**Request (Both Email + Phone):**
```json
{
  "email": "user@example.com",
  "password": "password123",
  "password_confirmation": "password123",
  "phone_number": "+919876543210"
}
```

**Response:**
```json
{
  "success": true,
  "user": {
    "id": 1,
    "email": "user@example.com",
    "phone_number": "+919876543210"
  },
  "message": "Registration successful. Please check your email for verification code.",
  "verification_required": true,
  "email_confirmed": false,
  "phone_verified": true
}
```
Note: `phone_verified: true` because phone verification is skipped when both are provided.

**Request (Phone Only):**
```json
{
  "password": "password123",
  "password_confirmation": "password123",
  "phone_number": "+919876543210"
}
```

**Response:**
```json
{
  "success": true,
  "user": {
    "id": 1,
    "phone_number": "+919876543210"
  },
  "message": "Registration successful. Please check your phone for verification code.",
  "verification_required": true,
  "email_confirmed": false,
  "phone_verified": false
}
```

**What Happens:**
1. User account created with `confirmed_at: null`, `phone_verified: false`
2. **Either/or logic:**
   - Both email + phone → Devise sends confirmation email only
   - Only phone → Send phone verification SMS
   - Only email → Devise sends confirmation email
3. Customer role assigned
4. API key generated (but not set in cookie yet)

---

## Verification Flow

### 2. Confirm Email (Devise Confirmable)

**Endpoint:** `POST /api/verification/confirm_email`

**Request:**
```json
{
  "confirmation_token": "token_from_devise_email"
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "Email confirmed successfully",
  "email_confirmed": true,
  "phone_verified": false,
  "fully_verified": false
}
```

### 3. Verify Phone

**Endpoint:** `POST /api/verification/verify_phone`

**Request:**
```json
{
  "phone_number": "+919876543210",
  "token": "verification_token_from_sms"
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "Phone verified successfully",
  "email_verified": true,
  "phone_verified": true,
  "fully_verified": true
}
```

---

## Login Flow

### 4. User Attempts Login

**Endpoint:** `POST /api/login`

**Request:**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response (Not Verified):**
```json
{
  "success": false,
  "message": "Please verify your email and phone number before logging in",
  "verification_required": true,
  "email_verified": false,
  "phone_verified": true,
  "email": "user@example.com",
  "phone_number": "+919876543210"
}
```
**Status:** `403 Forbidden`

**Response (Fully Verified):**
```json
{
  "success": true,
  "user": {
    "id": 1,
    "email": "user@example.com",
    "phone_number": "+919876543210",
    "email_verified": true,
    "phone_verified": true
  },
  "message": "Login successful"
}
```
**Status:** `200 OK`
**Cookie Set:** `spree_api_key` (encrypted, httponly)

---

## Resend Verification

### Resend Email Confirmation (Devise)

**Endpoint:** `POST /api/verification/resend_confirmation`

**Request:**
```json
{
  "email": "user@example.com"
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "Verification email sent"
}
```

**Response (Rate Limited):**
```json
{
  "error": "Please wait before requesting another verification email",
  "retry_after": 120
}
```
**Status:** `429 Too Many Requests`

### Resend Phone Verification

**Endpoint:** `POST /api/verification/resend_phone`

**Request:**
```json
{
  "phone_number": "+919876543210"
}
```

**Response:** Same as resend email

---

## Database Schema

### Devise Confirmable Columns (Email Verification)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `confirmation_token` | string | null | Devise token for email confirmation (indexed, unique) |
| `confirmed_at` | datetime | null | When email was confirmed |
| `confirmation_sent_at` | datetime | null | When confirmation email was sent |
| `unconfirmed_email` | string | null | Email being confirmed (for email changes) |

### Custom Phone Verification Columns

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `phone_verified` | boolean | false | Phone verification status |
| `phone_verification_token` | string | null | Secure token for phone verification (indexed, unique) |
| `phone_number` | string | null | User's phone number (indexed) |
| `phone_verification_sent_at` | datetime | null | When phone verification was sent |

### Indexes

- `confirmation_token` (unique) - Devise
- `phone_verification_token` (unique) - Custom
- `phone_number` - Custom

---

## User Model Methods

### Devise Confirmable Methods (Email)

```ruby
user.confirmed?                       # Check if email is confirmed
user.send_confirmation_instructions   # Send/resend confirmation email
user.confirm                          # Manually confirm email
Spree::User.confirm_by_token(token)  # Confirm email with token (returns user)
```

### Custom Phone Verification Methods

```ruby
user.send_phone_verification          # Send verification SMS
user.verify_phone!(token)             # Verify phone with token
user.phone_verified?                  # Check if phone is verified
user.can_resend_phone_verification?   # Check if can resend (rate limit)
```

### Combined Verification (Either/or Logic)

```ruby
# Either/or logic:
# - If both email and phone present → verify only email
# - If only phone present → verify only phone  
# - If only email present → verify only email

user.fully_verified?  # Check based on what's provided
```

### Example Usage

```ruby
# Scenario 1: User with both email and phone
user = Spree::User.find_by(email: 'test@example.com')
user.email.present?       # => true
user.phone_number.present?  # => true
user.fully_verified?      # => false (needs email confirmation only)
user.confirmed?           # => false (Devise)
user.confirm              # Confirm email (Devise method)
user.fully_verified?      # => true (email confirmed, phone not checked)

# Scenario 2: User with only phone
user = Spree::User.find_by(phone_number: '+919876543210')
user.email.blank?         # => true (or nil)
user.phone_number.present?  # => true
user.fully_verified?      # => false (needs phone verification)
user.phone_verified?      # => false
user.update!(phone_verified: true)  # Verify phone
user.fully_verified?      # => true (phone verified, email not checked)

# Scenario 3: User with only email
user = Spree::User.find_by(email: 'email-only@example.com')
user.email.present?       # => true
user.phone_number.blank?  # => true (or nil)
user.fully_verified?      # => false (needs email confirmation)
user.confirm              # Confirm email (Devise method)
user.fully_verified?      # => true (email confirmed, phone not checked)
```

---

## Mock SMS Service

**File:** `app/services/sms_service.rb`

In development, SMS codes are logged to console:

```
╔═══════════════════════════════════════════════════════╗
║              MOCK SMS SERVICE (Development)           ║
╠═══════════════════════════════════════════════════════╣
║ To: +919876543210                                     ║
║                                                       ║
║ Message:                                              ║
║ Your verification code is: AbC123                     ║
║                                                       ║
║ This code will expire in 10 minutes.                 ║
╚═══════════════════════════════════════════════════════╝
```

### Replacing with Real SMS Service

Edit `app/services/sms_service.rb`:

```ruby
def send_verification(phone_number, verification_code)
  if Rails.env.production?
    # Add your SMS provider (Twilio example):
    client = Twilio::REST::Client.new(
      ENV['TWILIO_ACCOUNT_SID'], 
      ENV['TWILIO_AUTH_TOKEN']
    )
    client.messages.create(
      from: ENV['TWILIO_PHONE_NUMBER'],
      to: phone_number,
      body: "Your verification code is: #{verification_code}"
    )
  else
    log_mock_sms(phone_number, verification_code)
  end
end
```

---

## Frontend Implementation

### Registration

```javascript
async function register(email, password, phoneNumber) {
  const response = await fetch('http://localhost:3001/api/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: JSON.stringify({
      email,
      password,
      password_confirmation: password,
      phone_number: phoneNumber
    })
  });
  
  const data = await response.json();
  
  if (data.verification_required) {
    // Show verification page
    showVerificationPage(data.user.email, data.user.phone_number);
  }
}
```

### Confirm Email (Devise)

```javascript
async function confirmEmail(confirmationToken) {
  const response = await fetch('http://localhost:3001/api/verification/confirm_email', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ confirmation_token: confirmationToken })
  });
  
  const data = await response.json();
  return data;  // { success, email_confirmed, phone_verified, fully_verified }
}
```

### Verify Phone

```javascript
async function verifyPhone(phoneNumber, token) {
  const response = await fetch('http://localhost:3001/api/verification/verify_phone', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone_number: phoneNumber, token })
  });
  
  const data = await response.json();
  return data;
}
```

### Login (After Verification)

```javascript
async function login(email, password) {
  const response = await fetch('http://localhost:3001/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: JSON.stringify({ email, password })
  });
  
  const data = await response.json();
  
  if (response.status === 403 && data.verification_required) {
    // Show verification page
    showVerificationPage(data.email, data.phone_number);
  } else if (data.success) {
    // Login successful, redirect to dashboard
    redirectToDashboard();
  }
}
```

---

## Testing

### In Development

1. **Register a user:**
```bash
curl -X POST http://localhost:3001/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123",
    "password_confirmation": "password123",
    "phone_number": "+919876543210"
  }'
```

2. **Check console for SMS token:**
Look for the mock SMS output in your Rails server logs.

3. **Check email:**
If using letter_opener gem or mailcatcher, open the verification email.

4. **Verify email:**
```bash
curl -X POST http://localhost:3001/api/verification/verify_email \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "token": "TOKEN_FROM_EMAIL"
  }'
```

5. **Verify phone:**
```bash
curl -X POST http://localhost:3001/api/verification/verify_phone \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+919876543210",
    "token": "TOKEN_FROM_SMS"
  }'
```

6. **Login:**
```bash
curl -X POST http://localhost:3001/api/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

### Manual Verification (Testing)

```ruby
# In Rails console
user = Spree::User.find_by(email: 'test@example.com')
user.update!(email_verified: true, phone_verified: true)
```

---

## Files Created/Modified

### Created
- `db/migrate/XXXXXX_add_verification_fields_to_spree_users.rb` - Phone verification columns
- `db/migrate/XXXXXX_remove_custom_email_verification_from_spree_users.rb` - Remove custom email columns
- `app/models/concerns/user_verification.rb` - Phone verification logic
- `config/initializers/user_verification_extension.rb` - Include concern in User
- `config/initializers/devise_confirmable.rb` - Enable Devise confirmable
- `app/services/sms_service.rb` - Mock SMS service
- `app/controllers/api/verification_controller.rb` - Verification endpoints

### Modified
- `config/routes.rb` - Added verification endpoints
- `app/controllers/api/auth_controller.rb` - Updated login/register to check both verifications

### Using Devise
- Email confirmation handled by Devise confirmable (built-in)
- No custom email templates needed (Devise provides them)

---

## Security Features

1. **Secure Tokens:** Uses `SecureRandom.urlsafe_base64(32)` - cryptographically secure
2. **Unique Indexes:** Prevents token collisions
3. **Rate Limiting:** 2-minute cooldown between resend requests
4. **Token Expiry:** Recommended to implement 24-hour expiry (add logic in verify methods)
5. **One-Time Use:** Tokens deleted after successful verification

---

## Production Checklist

Before going to production:

- [ ] Replace `SmsService` with real SMS provider (Twilio, AWS SNS, etc.)
- [ ] Set `FRONTEND_URL` environment variable
- [ ] Configure email delivery (SMTP, SendGrid, etc.)
- [ ] Add token expiration logic (24 hours recommended)
- [ ] Set up email templates with your branding
- [ ] Test email deliverability
- [ ] Test SMS delivery in production
- [ ] Add monitoring for verification failures
- [ ] Consider adding captcha to prevent spam registrations

---

## Troubleshooting

### Email Not Received
- Check Rails logs for email sending
- Verify email configuration in `config/environments/development.rb`
- Use `letter_opener` gem to view emails in development

### SMS Not Working in Development
- Check Rails console output - mock SMS is logged there
- Check server logs for SMS service output

### "Verification Required" Error on Login
- User hasn't verified email or phone
- Check user status: `Spree::User.find_by(email: '...').fully_verified?`
- Manually verify for testing (see Testing section above)

---

## API Endpoints Summary

| Endpoint | Method | Purpose | Auth Required |
|----------|--------|---------|---------------|
| `/api/register` | POST | Create account, send verifications | No |
| `/api/login` | POST | Login (requires full verification) | No |
| `/api/verification/confirm_email` | POST | Confirm email with Devise token | No |
| `/api/verification/verify_phone` | POST | Verify phone with OTP token | No |
| `/api/verification/resend_confirmation` | POST | Resend Devise confirmation email | No |
| `/api/verification/resend_phone` | POST | Resend phone verification SMS | No |

---

**System is ready! Users must verify both email and phone before they can log in.** 🎉

