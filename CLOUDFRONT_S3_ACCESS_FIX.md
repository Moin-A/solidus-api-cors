# CloudFront Access Denied - Fix Guide

## Problem

Getting this error when accessing CloudFront URLs:
```xml
<Error>
  <Code>AccessDenied</Code>
  <Message>Access Denied</Message>
</Error>
```

**Example URL:** `https://d3687nk8qb4e0v.cloudfront.net/avbql4zuosgd1q9ud5cit04p92g`

## Root Cause

CloudFront distribution doesn't have permission to read objects from your S3 bucket.

---

## Solution 1: Using Origin Access Control (OAC) - Recommended ⭐

Origin Access Control is the **modern, AWS-recommended** approach (released 2022).

### Step 1: Create Origin Access Control

1. Go to **AWS CloudFront Console**: https://console.aws.amazon.com/cloudfront/
2. Click on your distribution ID: `d3687nk8qb4e0v.cloudfront.net`
3. Go to **Origins** tab
4. Select your S3 origin
5. Click **Edit**
6. Under **Origin access**, select **Origin access control settings (recommended)**
7. Click **Create control setting** (or select existing one)
   - Name: `solidus-s3-oac`
   - Signing behavior: **Sign requests (recommended)**
   - Origin type: **S3**
8. Click **Create**
9. Click **Save changes**

### Step 2: Update S3 Bucket Policy

AWS will show you a **policy** after creating OAC. Copy it!

If you missed it, here's the policy template:

1. Go to **S3 Console**: https://console.aws.amazon.com/s3/
2. Find your bucket (check `AWS_S3_BUCKET` env var or check CloudFront origin)
3. Go to **Permissions** tab
4. Scroll to **Bucket policy**
5. Click **Edit**
6. Add this policy (replace values):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::YOUR-ACCOUNT-ID:distribution/YOUR-DISTRIBUTION-ID"
        }
      }
    }
  ]
}
```

**Replace:**
- `YOUR-BUCKET-NAME` - Your S3 bucket name
- `YOUR-ACCOUNT-ID` - Your AWS account ID (12 digits)
- `YOUR-DISTRIBUTION-ID` - Your CloudFront distribution ID (starts with E...)

### Step 3: Get Your Values

**Find your bucket name:**
```bash
# Check environment variable
echo $AWS_S3_BUCKET
```

**Find your CloudFront distribution ID:**
```bash
# Go to CloudFront console, or from URL:
# https://d3687nk8qb4e0v.cloudfront.net
# The distribution ID is in CloudFront console (format: E1234567890ABC)
```

**Find your AWS Account ID:**
```bash
# In AWS Console, click your username (top right) → Account
# Or use AWS CLI:
aws sts get-caller-identity --query Account --output text
```

### Step 4: Example Complete Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::solidus-storage-production/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"
        }
      }
    }
  ]
}
```

### Step 5: Wait and Test

- CloudFront changes take **5-10 minutes** to propagate
- Test your URL: `https://d3687nk8qb4e0v.cloudfront.net/avbql4zuosgd1q9ud5cit04p92g`
- Should now work! 🎉

---

## Solution 2: Using Origin Access Identity (OAI) - Legacy

If you prefer the older method (still works fine):

### Step 1: Create Origin Access Identity

1. Go to **CloudFront Console**
2. Click on your distribution
3. Go to **Origins** tab
4. Select your S3 origin
5. Click **Edit**
6. Under **Origin access**, select **Legacy access identities**
7. Create new OAI or select existing one
8. **Important:** Check **Yes, update the bucket policy**
9. Click **Save changes**

AWS will automatically update your S3 bucket policy!

### Step 2: Verify S3 Bucket Policy

Go to S3 → Your bucket → Permissions → Bucket policy

Should look like:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontOAI",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity E1234567890ABC"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::solidus-storage-production/*"
    }
  ]
}
```

---

## Solution 3: Quick Test - Make Bucket Public (NOT RECOMMENDED for Production)

⚠️ **Only for testing/debugging! Remove after testing!**

### Make S3 Bucket Public

1. Go to S3 Console
2. Select your bucket
3. Go to **Permissions** tab
4. **Block public access** - Click Edit
5. Uncheck "Block all public access"
6. Save changes
7. Go to **Bucket policy**
8. Add this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*"
    }
  ]
}
```

⚠️ **This makes ALL files publicly accessible! Only for testing!**

---

## Debugging Steps

### 1. Check if file exists in S3

```bash
# List files in bucket (requires AWS CLI configured)
aws s3 ls s3://YOUR-BUCKET-NAME/ --recursive | grep avbql4zuosgd1q9ud5cit04p92g
```

### 2. Test direct S3 URL (will fail if private - which is good!)

```
https://YOUR-BUCKET-NAME.s3.amazonaws.com/avbql4zuosgd1q9ud5cit04p92g
```

Should get Access Denied → Good! Bucket is private.

### 3. Check CloudFront Origin Settings

1. Go to CloudFront Console
2. Click your distribution
3. Go to **Origins** tab
4. Verify:
   - Origin domain points to your S3 bucket
   - Origin access is configured (OAC or OAI)

### 4. Check CloudFront Distribution Status

- Status should be **Deployed**
- If **In Progress**, wait for deployment to complete (5-10 mins)

### 5. Test in Rails Console

```ruby
# Check environment
Rails.env
# => "production"

# Check storage service
Rails.application.config.active_storage.service
# => :amazon

# Get URL
taxon = Spree::Taxon.find(2)
taxon.attachment_url
# => "https://d3687nk8qb4e0v.cloudfront.net/avbql4zuosgd1q9ud5cit04p92g"

# Check if blob exists
taxon.icon.blob.key
# => "avbql4zuosgd1q9ud5cit04p92g"
```

---

## Common Issues

### Issue 1: "NoSuchBucket" Error

**Problem:** CloudFront origin pointing to wrong S3 bucket

**Fix:**
1. Go to CloudFront → Origins
2. Check origin domain name matches your S3 bucket
3. Should be: `YOUR-BUCKET-NAME.s3.amazonaws.com`

### Issue 2: "AccessDenied" persists after policy update

**Problem:** CloudFront cache still has old error

**Fix:**
1. Go to CloudFront Console
2. Select your distribution
3. Go to **Invalidations** tab
4. Click **Create invalidation**
5. Enter: `/*` (invalidates everything)
6. Click **Create**
7. Wait 5 minutes and test again

### Issue 3: CORS errors in browser

**Problem:** S3 bucket CORS not configured

**Fix:**
1. Go to S3 Console → Your bucket
2. Go to **Permissions** → **CORS**
3. Add:

```json
[
  {
    "AllowedHeaders": ["*"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedOrigins": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
```

---

## Recommended Configuration Summary

### For Production (Best Practice):

1. **S3 Bucket:**
   - Private (Block all public access: ON)
   - Bucket policy: Allow CloudFront via OAC
   - CORS configured

2. **CloudFront:**
   - Origin Access Control (OAC) configured
   - Origin: S3 bucket
   - Behavior: Redirect HTTP to HTTPS
   - Cache policy: CachingOptimized (or custom)

3. **Rails Configuration:**
   - `config.active_storage.service = :amazon`
   - CloudFront URL in initializer
   - Environment variable: `CLOUDFRONT_URL=https://d3687nk8qb4e0v.cloudfront.net`

---

## Quick Fix Checklist

- [ ] CloudFront distribution deployed and active
- [ ] Origin Access Control (OAC) or Origin Access Identity (OAI) created
- [ ] S3 bucket policy updated to allow CloudFront
- [ ] Waited 5-10 minutes for changes to propagate
- [ ] Tested URL: `https://d3687nk8qb4e0v.cloudfront.net/avbql4zuosgd1q9ud5cit04p92g`
- [ ] If still failing, created CloudFront invalidation
- [ ] Verified file exists in S3 bucket

---

## Environment Variables to Check

```bash
# In production
echo $AWS_S3_BUCKET           # Your S3 bucket name
echo $AWS_REGION              # Should be us-east-1 or your region
echo $CLOUDFRONT_URL          # https://d3687nk8qb4e0v.cloudfront.net
echo $AWS_ACCESS_KEY_ID       # Should be set
echo $AWS_SECRET_ACCESS_KEY   # Should be set (hidden)
```

---

## Testing After Fix

```bash
# Test CloudFront URL
curl -I https://d3687nk8qb4e0v.cloudfront.net/avbql4zuosgd1q9ud5cit04p92g

# Should return:
# HTTP/2 200
# content-type: image/webp
# x-cache: Hit from cloudfront  (or Miss from cloudfront - both OK)
```

---

## Need More Help?

If Access Denied persists:

1. **Check AWS CloudTrail** for detailed error logs
2. **Check S3 Server Access Logs** (if enabled)
3. **Verify IAM permissions** for your AWS user/role
4. **Contact AWS Support** with distribution ID and bucket name

---

## Related Files

- `config/initializers/active_storage_cloudfront.rb` - CloudFront URL override
- `config/storage.yml` - S3 configuration
- `app/models/concerns/spree/active_storage_adapter.rb` - attachment_url method

---

**Last Updated:** December 2, 2025





