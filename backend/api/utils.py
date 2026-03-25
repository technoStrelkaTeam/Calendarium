from __future__ import annotations

from datetime import timedelta, datetime, timezone
import bcrypt
import jwt
import imaplib
import email
from email.header import decode_header
import base64
import html
import re
import socket

from api.config import SECRET_KEY, ALGORITHM

IMAP_SERVERS = {
    "mail.ru": "imap.mail.ru",
    "bk.ru": "imap.mail.ru",
    "inbox.ru": "imap.mail.ru",
    "internet.ru": "imap.mail.ru",
    "list.ru": "imap.mail.ru",
    "yandex.ru": "imap.yandex.ru",
    "ya.ru": "imap.yandex.ru",
    "yandex.com": "imap.yandex.com",
    "yandex.ua": "imap.yandex.ua",
    "yandex.kz": "imap.yandex.kz",
    "yandex.by": "imap.yandex.by",
    "gmail.com": "imap.gmail.com",
    "outlook.com": "outlook.office365.com",
    "hotmail.com": "outlook.office365.com",
    "live.com": "outlook.office365.com",
}


def hash_password(password: str) -> bytes:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt())


def check_password(password: str, hash_passw: str) -> bool:
    return bcrypt.checkpw(password.encode(), hash_passw.encode())


def create_access_token(data: dict, expires_delta: timedelta | None = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=15))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def connect_to_the_mail(login: str, password: str, debug: bool = False) -> dict:
    domain = login.split("@")[1].lower()
    server = IMAP_SERVERS.get(domain, f"imap.{domain}")
    port = 993

    if debug:
        print(f"Domain: {domain}")
        print(f"Server: {server}:{port}")
        print(f"Login: {login}")

    imap = None
    try:
        if debug:
            print("Step 1: Creating SSL connection...")

        imap = imaplib.IMAP4_SSL(server, port, timeout=10)

        if debug:
            print("Step 2: SSL connected, trying login...")

        imap.login(login, password)

        if debug:
            print("Step 3: Login successful, selecting INBOX...")

        imap.select("INBOX")

        if debug:
            print("Step 4: INBOX selected, searching messages...")

        trigger_words = ["подписк", "сумма", "списан"]
        triggers = []
        for word in trigger_words:
            triggers.append('TEXT')
            triggers.append(word.encode('utf-8'))

        status, data = imap.search('UTF-8', *triggers)

        if debug:
            print(f"Messages found: {len(data[0].split())}")

        mail_ids = data[0].split()
        subs = {}

        for i in reversed(mail_ids):
            try:
                if debug:
                    print(f"Processing message {i}...")

                res, msg = imap.fetch(i, '(RFC822)')
                msg = email.message_from_bytes(msg[0][1])
                letter_date = email.utils.parsedate_tz(msg["Date"])

                from_header = decode_header(msg["From"])[0]
                letter_from = from_header[0].decode() if isinstance(from_header[0], bytes) else str(from_header[0])

                subject_header = decode_header(msg["Subject"])[0]
                text_header = subject_header[0].decode() if isinstance(subject_header[0], bytes) else str(
                    subject_header[0])

                text = ""
                if msg.is_multipart():
                    for part in msg.walk():
                        if part.get_content_maintype() == 'text' and part.get_content_subtype() == 'plain':
                            payload = part.get_payload(decode=True)
                            if payload:
                                text = html.unescape(payload.decode(errors='ignore'))
                else:
                    payload = msg.get_payload(decode=True)
                    if payload:
                        text = html.unescape(payload.decode("utf-8", errors='ignore'))

                cost_match = re.search(r"[\d\s]+₽", text)
                flag_match = re.search(r"сумма", text.lower())

                if cost_match and flag_match:
                    cost = cost_match.group()[:-1].replace(" ", "")
                    name = f"{text_header} - {letter_from}"

                    if name in subs:
                        if "interval" not in subs[name] and letter_date:
                            y = subs[name]["next_pay"][0] - letter_date[0]
                            m = subs[name]["next_pay"][1] - letter_date[1]
                            d = subs[name]["next_pay"][2] - letter_date[2]
                            if y and not m and not d:
                                subs[name]["interval"] = y
                                subs[name]["type_interval"] = "year"
                            elif m and not y and not d:
                                subs[name]["interval"] = m
                                subs[name]["type_interval"] = "month"
                            elif d and not y and not m:
                                subs[name]["interval"] = d
                                subs[name]["type_interval"] = "day"
                    else:
                        subs[name] = {
                            "cost": int(cost),
                            "next_pay": list(letter_date[:3]) if letter_date else [0, 0, 0]
                        }

                    if debug:
                        print(f"  Found subscription: {name}, cost: {cost}")

            except Exception as e:
                if debug:
                    print(f"  Error parsing message: {e}")
                continue

        if debug:
            print(f"Total subscriptions found: {len(subs)}")

        return subs

    except socket.timeout:
        if debug:
            print(f"ERROR: Connection timed out to {server}:{port}")
        raise Exception(f"Connection timed out to {server}:{port}. Check firewall and internet connection.")
    except imaplib.IMAP4.error as e:
        if debug:
            print(f"IMAP Error: {e}")
        raise Exception(f"IMAP error: {e}")
    except Exception as e:
        if debug:
            print(f"Unexpected error: {type(e).__name__}: {e}")
        raise
    finally:
        if imap:
            try:
                imap.logout()
                if debug:
                    print("Connection closed")
            except:
                pass


if __name__ == "__main__":
    test_subs = connect_to_the_mail("your@email", "password_imap", debug=True)
    print(test_subs)
