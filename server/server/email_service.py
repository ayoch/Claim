"""Email sending service for password resets and notifications."""

import logging
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from server.config import settings

logger = logging.getLogger(__name__)


def send_password_reset_email(to_email: str, username: str, reset_token: str) -> bool:
    """
    Send password reset email with reset link.
    Returns True if sent successfully, False otherwise.
    """
    if not settings.SMTP_ENABLED:
        logger.warning(f"SMTP disabled - would send reset email to {to_email}")
        logger.info(f"Password reset token for {username}: {reset_token}")
        return True  # Succeed in dev mode so we can test without real email

    try:
        # Create reset link
        reset_url = f"{settings.FRONTEND_URL}/reset-password?token={reset_token}"

        # Create email
        msg = MIMEMultipart("alternative")
        msg["Subject"] = "Claim - Password Reset Request"
        msg["From"] = settings.SMTP_FROM_EMAIL
        msg["To"] = to_email

        # Plain text version
        text = f"""
Hello {username},

You requested a password reset for your Claim account.

Click the link below to reset your password (expires in 1 hour):
{reset_url}

If you didn't request this, you can safely ignore this email.

Best regards,
The Claim Team
"""

        # HTML version
        html = f"""
<html>
<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
    <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="color: #2c3e50;">Password Reset Request</h2>
        <p>Hello <strong>{username}</strong>,</p>
        <p>You requested a password reset for your Claim account.</p>
        <p>Click the button below to reset your password:</p>
        <div style="margin: 30px 0;">
            <a href="{reset_url}" style="background-color: #3498db; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; display: inline-block;">
                Reset Password
            </a>
        </div>
        <p style="color: #7f8c8d; font-size: 14px;">
            This link will expire in <strong>1 hour</strong>.
        </p>
        <p style="color: #7f8c8d; font-size: 14px;">
            If you didn't request this, you can safely ignore this email.
        </p>
        <hr style="border: none; border-top: 1px solid #ecf0f1; margin: 30px 0;">
        <p style="color: #95a5a6; font-size: 12px;">
            The Claim Team<br>
            Space Mining Simulation
        </p>
    </div>
</body>
</html>
"""

        msg.attach(MIMEText(text, "plain"))
        msg.attach(MIMEText(html, "html"))

        # Send email
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
            if settings.SMTP_TLS:
                server.starttls()
            if settings.SMTP_USERNAME and settings.SMTP_PASSWORD:
                server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
            server.send_message(msg)

        logger.info(f"Password reset email sent to {to_email}")
        return True

    except Exception as e:
        logger.error(f"Failed to send password reset email to {to_email}: {e}")
        return False


def send_welcome_email(to_email: str, username: str) -> bool:
    """
    Send welcome email to new users.
    Returns True if sent successfully, False otherwise.
    """
    if not settings.SMTP_ENABLED:
        logger.warning(f"SMTP disabled - would send welcome email to {to_email}")
        return True

    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = "Welcome to Claim!"
        msg["From"] = settings.SMTP_FROM_EMAIL
        msg["To"] = to_email

        text = f"""
Welcome to Claim, {username}!

Your account has been created successfully. You can now log in and start your asteroid mining empire!

Visit {settings.FRONTEND_URL} to get started.

Best regards,
The Claim Team
"""

        html = f"""
<html>
<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
    <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="color: #2c3e50;">Welcome to Claim!</h2>
        <p>Hello <strong>{username}</strong>,</p>
        <p>Your account has been created successfully. You're ready to start your asteroid mining empire!</p>
        <div style="margin: 30px 0;">
            <a href="{settings.FRONTEND_URL}" style="background-color: #27ae60; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; display: inline-block;">
                Start Mining
            </a>
        </div>
        <p>Good luck out there in the belt!</p>
        <hr style="border: none; border-top: 1px solid #ecf0f1; margin: 30px 0;">
        <p style="color: #95a5a6; font-size: 12px;">
            The Claim Team<br>
            Space Mining Simulation
        </p>
    </div>
</body>
</html>
"""

        msg.attach(MIMEText(text, "plain"))
        msg.attach(MIMEText(html, "html"))

        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
            if settings.SMTP_TLS:
                server.starttls()
            if settings.SMTP_USERNAME and settings.SMTP_PASSWORD:
                server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
            server.send_message(msg)

        logger.info(f"Welcome email sent to {to_email}")
        return True

    except Exception as e:
        logger.error(f"Failed to send welcome email to {to_email}: {e}")
        return False
