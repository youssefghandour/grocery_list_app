# Finalize Secure Backend Payment Integration

We have implemented secure Google Play verification on the backend and verified that the necessary permissions have been granted in the Google Play Console. This plan will finalize the configuration and deployment.

## User Review Required

> [!IMPORTANT]
> To enable **Google Play** verification, the `GOOGLE_PLAY_ENABLED` flag must be set to `true` in the functions environment. This is currently configured in your local `.env.animemusic-e8c09` file.
>
> To enable **Paymob**, you will need to provide your `PAYMOB_SECRET_KEY` and `PAYMOB_HMAC_SECRET` as Firebase secrets.

## Proposed Changes

### Backend Configuration

#### [MODIFY] [.env.animemusic-e8c09](file:///C:/Users/youss/StudioProjects/grocery_list_app/functions/.env.animemusic-e8c09)
Ensure `GOOGLE_PLAY_ENABLED=true` is set.

### Deployment

1. **Deploy Cloud Functions**: Apply the environment variables and code changes to the live Firebase environment.
2. **Verify Access**: Run the diagnostic script to confirm the backend can reach the Google Play Developer API.

## Verification Plan

### Automated Tests
- Run `npm --prefix functions run lint` to ensure code quality.
- Run `node --test qa/google-play.test.cjs` to verify verification logic with mocks.

### Manual Verification
- Deploy functions and check logs for any startup errors.
- Confirm `getPaymentCapabilities` returns `nativeStore: true` for Android clients.
