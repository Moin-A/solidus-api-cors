# Testing Admin Login

## To test the fix:

1. Navigate to: http://localhost:3001/admin/login
2. Enter your admin credentials
3. Check if you're redirected to `/admin` instead of `/`

## To view the logs:

```bash
tail -100 log/development.log | grep -A 50 "LOGIN CREATE DEBUG"
```

## What was changed:

The issue was that `warden.set_user` was failing and returning a 401 Unauthorized status, causing the browser to redirect to the root path (`/`) which maps to `HomeController#index`.

The fix replaced `warden.set_user` with Devise's `sign_in` helper which properly handles:
- Setting the user in the warden session
- Running necessary callbacks
- Updating tracking fields
- Managing the authentication state

## Expected behavior:

After successful login, you should see in the logs:
- "Password is valid, signing in user"
- "sign_in completed successfully"
- "Redirect path: /admin"
- A 302 redirect to /admin (not 401)








