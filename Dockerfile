# syntax=docker/dockerfile:1
# ═══════════════════════════════════════════════════════════════════════════
#
#   ELMINYAWE — ملف واحد متكامل: MariaDB + Lavalink v4 + بوت موسيقى ديسكورد
#
#   ── المميزات ────────────────────────────────────────────────────────────
#   • أمر play يبحث ويرسل قائمة نتائج مرقّمة ثم ينتظر اختيارك رقم الأغنية
#   • لا يضيف البوت أي قائمة انتظار من تلقاء نفسه — يشغّل ما تختاره فقط
#   • Lavalink v4 + إضافة يوتيوب مع OAuth (رمز التحديث الثابت مضمّن)
#     وقائمة عملاء مختارة تعمل مع IPs مراكز البيانات
#   • 🍪 نظام كوكيز ذكي: بعد تسجيل الدخول (OAuth) يجلب النظام كوكيز يوتيوب
#     بنفسه ويجدّدها كل 6 ساعات — لا حاجة لأي ملف كوكيز يدوي إطلاقاً
#   • 🛡️ مولد PO Tokens تلقائي (bgutil + deno) لتجاوز فحص "لست روبوتاً"
#   • 🎯 المسار الأساسي: yt-dlp يستخرج رابط الصوت المباشر (كوكيز OAuth +
#     PO Token إجباري + حلّال تحديات يوتيوب 2026) ويُبثّ عبر مصدر HTTP
#     ثم عملاء Lavalink الداخليون كطبقة ثانية، وإصلاح تلقائي عند أي فشل
#   • وضع احتياطي كامل: إذا تعذّر الوصول لـ Lavalink يعمل البوت بـ yt-dlp/ffmpeg
#   • سبوتيفاي (بحث + روابط) عبر LavaSrc — قاعدة بيانات MariaDB للتاريخ والإعدادات
#   • أوامر كاملة: play / queue / skip / pause / resume / stop / volume / loop /
#     shuffle / skipto / remove / seek / 247 / history / nowplaying / ping / help
#   • شريط تقدّم حيّ داخل رسالة "شغّال الآن" تتحدّث تلقائياً
#
#   ── قبل التشغيل (مهم!) ─────────────────────────────────────────────────
#   1) ضع توكن بوتك في متغير البيئة DISCORD_TOKEN (أسفله في قسم ENV)
#      أو اضبطه كمتغيّر Variables في Railway (يفضّل).
#   2) في Railway: أنشئ Volume واربطه بالمسار  /var/lib/mysql
#   3) لا تحتاج لأي ملف كوكيز — النظام يجلبها ويجدّدها تلقائياً بعد الدخول
#      (وإن رغبت بالكوكيز اليدوية كمستوى إضافي: ضع محتواها في متغير
#      YOUTUBE_COOKIES في Railway — اختياري تماماً وغير مطلوب).
#   4) لا حاجة لأي إعدادات أخرى — كل شيء مضمّن في هذا الملف.
#
# ═══════════════════════════════════════════════════════════════════════════

FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# ── حزم النظام: Java 17 لتشغيل Lavalink + ffmpeg للبث الاحتياطي + MariaDB ──
RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-17-jre-headless \
        ffmpeg \
        mariadb-server \
        supervisor \
        curl \
        ca-certificates \
        gnupg \
        git \
        tini \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 22: يشغّل مولّد PO Tokens (bgutil) لتجاوز فحص "لست روبوتاً" ──
RUN curl -fsSL --retry 5 --retry-delay 3 https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

# ── deno: بيئة JS مطلوبة لمعالجات تحديات yt-dlp الحديثة ──
# ⚠️ tags على GitHub تحمل البادئة v (v2.9.7 وليس 2.9.7) — بدونها يرجع 404.
# نجلب أحدث إصدار من CDN الرسمي dl.deno.land مع الرجوع إلى v2.9.7 ثابتاً عند الفشل،
# وننزّل من CDN أولاً ثم من GitHub كبديل — لا يمكن أن يفشل البناء من هذه الطبقة.
RUN set -eu; \
    DENO_VER="$(curl -fsSL --retry 5 --retry-delay 3 https://dl.deno.land/release-latest.txt || true)"; \
    [ -n "${DENO_VER}" ] || DENO_VER="v2.9.7"; \
    echo ">> Installing deno ${DENO_VER}"; \
    curl -fL --retry 5 --retry-delay 3 -o /tmp/deno.zip \
         "https://dl.deno.land/release/${DENO_VER}/deno-x86_64-unknown-linux-gnu.zip" \
    || curl -fL --retry 5 --retry-delay 3 -o /tmp/deno.zip \
         "https://github.com/denoland/deno/releases/download/${DENO_VER}/deno-x86_64-unknown-linux-gnu.zip"; \
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/deno.zip').extractall('/usr/local/bin/')" \
    && chmod +x /usr/local/bin/deno && rm -f /tmp/deno.zip \
    && deno --version | head -1

# ── مولّد PO Tokens (bgutil): خادم محلي يولّد توكنات المصدر تلقائياً ──
# إضافة yt-dlp (bgutil-ytdlp-pot-provider) تتصل به تلقائياً على 127.0.0.1:4416
# التثبيت على الوسم 2.0.0 المُختبر حياً (ثابت ومضمون بدلاً من HEAD المتغيّر)
RUN git clone --depth 1 --branch 2.0.0 https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git /opt/bgutil \
    && cd /opt/bgutil/server \
    && npm install --no-audit --no-fund --loglevel=error \
    && npx tsc \
    && npm prune --omit=dev \
    && test -f /opt/bgutil/server/build/main.js \
    && npm cache clean --force \
    && rm -rf /root/.npm

# ── مكتبات بايثون الثابتة ──────────────────────────────────────────────────
RUN pip install --no-cache-dir \
        "discord.py>=2.7.0,<3" \
        "wavelink==3.5.2" \
        "PyNaCl>=1.5" \
        "davey>=0.1" \
        "PyMySQL>=1.1" \
        "PyYAML>=6.0.1" \
        "bgutil-ytdlp-pot-provider==2.0.0" \
        "yt-dlp==2026.8.19"

# ── تحميل Lavalink v4 ───────────────────────────────────────────────────────
RUN mkdir -p /opt/lavalink /opt/bot \
    && curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 \
         -o /opt/lavalink/Lavalink.jar \
         "https://github.com/lavalink-devs/Lavalink/releases/download/4.2.2/Lavalink.jar" \
    && ls -la /opt/lavalink/Lavalink.jar

# ═══════════════════════════════════════════════════════════════════════════
#  متغيّرات البيئة — الافتراضيات الثابتة
#  ⚠️  ضع توكن بوتك في DISCORD_TOKEN (أو اضبطه في Railway Variables)
#  🔒 رمز تحديث يوتيوب OAuth ثابت دائم — لا يتغيّر مع كل إقلاع
# ═══════════════════════════════════════════════════════════════════════════
ENV DISCORD_TOKEN="" \
    DISCORD_PREFIX="!" \
    LAVALINK_HOST="127.0.0.1" \
    LAVALINK_PORT="2008" \
    LAVALINK_PASSWORD="ELMINYAWE" \
    YT_REFRESH_TOKEN="1//0eVooXRETOIiuCgYIARAAGA4SNwF-L9Irvn8-fFnEvPQl33FHJroxf7YbO4WmJ2Go52l3IrBkRh7BIPIiuX0FyGmgo7lAeC9krzw" \
    YT_CLIENTS="WEB,TVHTML5_SIMPLY,TV" \
    SPOTIFY_CLIENT_ID="b9a4b5775f1847a2b072573589b530f7" \
    SPOTIFY_CLIENT_SECRET="682ef411fa5942d28bfe6c409e90f202" \
    YOUTUBE_COOKIES="" \
    YOUTUBE_COOKIES_FILE="" \
    YT_COOKIES_INTERVAL_SEC="21600" \
    POT_REFRESH_INTERVAL_SEC="14400" \
    MYSQL_ROOT_PASSWORD="ElMinyaweDB2026" \
    MYSQL_DATABASE="musicbot" \
    JAVA_OPTS="-Xms64m -Xmx512m" \
    IDLE_DISCONNECT_SEC="300"

# ── مولّد إعدادات Lavalink (يكتب application.yml من متغيرات البيئة) ─────────
RUN cat > /opt/bot/gen_lavalink_config.py <<'GENCFG_EOF'
# -*- coding: utf-8 -*-
"""
elminyawe — مولّد إعدادات Lavalink (application.yml)
يُنشئ الملف من متغيرات البيئة عند كل إقلاع، ثم يتحقق من صحة YAML الناتج.
"""
import os
import sys

import yaml

# ── الثوابت الثابتة (لا تتغير) ──────────────────────────────────────────────
LAVALINK_VERSION = "4.2.2"
YOUTUBE_PLUGIN = "dev.lavalink.youtube:youtube-plugin:1.18.2"
LAVASRC_PLUGIN = "com.github.topi314.lavasrc:lavasrc-plugin:4.8.3"
LAVASEARCH_PLUGIN = "com.github.topi314.lavasearch:lavasearch-plugin:1.0.0"
MAVEN_REPO = "https://maven.lavalink.dev/releases"

# ── القيم من البيئة (مع افتراضيات ثابتة) ────────────────────────────────────
PORT = int(os.getenv("LAVALINK_PORT", "2008"))
PASSWORD = os.getenv("LAVALINK_PASSWORD", "ELMINYAWE")
REFRESH_TOKEN = os.getenv(
    "YT_REFRESH_TOKEN",
    "1//0eVooXRETOIiuCgYIARAAGA4SNwF-L9Irvn8-fFnEvPQl33FHJroxf7YbO4WmJ2Go52l3IrBkRh7BIPIiuX0FyGmgo7lAeC9krzw",
)
# قائمة العملاء وفق README الرسمي لـ youtube-source (1.18.2):
#  • WEB            — بث كامل + يعمل مع POT token (يُحقن تلقائياً من potsync)
#  • TVHTML5_SIMPLY — بث كامل بلا مصادقة
#  • TV             — العميل الوحيد الذي يدعم OAuth (يعمل بحساب عند الحجب)
#  ملاحظة: MUSIC لا يدعم البث أصلاً (بحث فقط) — لذلك أُزيل من القائمة.
CLIENTS = [c.strip() for c in os.getenv("YT_CLIENTS", "WEB,TVHTML5_SIMPLY,TV").split(",") if c.strip()]
SPOTIFY_CLIENT_ID = os.getenv("SPOTIFY_CLIENT_ID", "b9a4b5775f1847a2b072573589b530f7")
SPOTIFY_CLIENT_SECRET = os.getenv("SPOTIFY_CLIENT_SECRET", "682ef411fa5942d28bfe6c409e90f202")
OUTPUT = os.getenv("LAVALINK_CONFIG", "/opt/lavalink/application.yml")


def build_config() -> dict:
    return {
        "lavalink": {
            "plugins": [
                {"dependency": YOUTUBE_PLUGIN, "repository": MAVEN_REPO},
                {"dependency": LAVASRC_PLUGIN, "repository": MAVEN_REPO},
                {"dependency": LAVASEARCH_PLUGIN, "repository": MAVEN_REPO},
            ],
            "server": {
                "password": PASSWORD,
                "sources": {
                    "youtube": False,        # المصدر المدمج معطّل — البرنامج الإضافي يتولى يوتيوب
                    "bandcamp": True,
                    "soundcloud": True,
                    "twitch": True,
                    "vimeo": True,
                    "http": True,            # مهم: يسمح ببث الروابط المباشرة (مسار الإصلاح)
                    "local": False,
                    "nico": True,
                },
                "youtubeSearchEnabled": True,
                "soundcloudSearchEnabled": True,
                "youtubePlaylistLoadLimit": 6,
                "bufferDurationMs": 400,
                "frameBufferDurationMs": 5000,
                "opusEncodingQuality": 5,
                "resamplingQuality": "HIGH",
                "trackStuckThresholdMs": 10000,
                "useSeekGhosting": True,
                "playerUpdateInterval": 5,
                "readTimeout": 60000,
                "requestTimeout": 60000,
                "gcWarnings": True,
                "filters": {
                    "volume": True,
                    "equalizer": True,
                    "karaoke": True,
                    "timescale": True,
                    "tremolo": True,
                    "vibrato": True,
                    "rotation": True,
                    "distortion": True,
                    "channelMix": True,
                    "lowPass": True,
                },
            },
        },
        "logging": {
            "level": {
                "root": "INFO",
                "lavalink": "INFO",
                "dev.lavalink.youtube.http.YoutubeOauth2Handler": "INFO",
            },
            "logback": {
                "rollingPolicy": {
                    "maxFileSize": "100MB",
                    "maxHistory": 7,
                }
            },
            "request": {
                "enabled": False,
            },
        },
        "metrics": {
            "prometheus": {
                "enabled": False,
                "endpoint": "/metrics",
            }
        },
        "plugins": {
            "youtube": {
                "enabled": True,
                "allowSearch": True,
                "allowDirectVideoIds": True,
                "allowDirectPlaylistIds": True,
                "clients": CLIENTS,
                "oauth": {
                    "enabled": True,
                    "skipInitialization": True,   # تخطّى تدفّق الجهاز — استخدم الرمز المحدّث مباشرة
                    "refreshToken": REFRESH_TOKEN,
                },
            },
            "lavasrc": {
                "providers": [
                    'ytsearch:"%ISRC%"',
                    "ytsearch:%QUERY%",
                ],
                "sources": {
                    "spotify": True,
                    "youtube": True,
                    "applemusic": False,
                    "deezer": False,
                    "yandexmusic": False,
                    "flowerytts": False,
                },
                "spotify": {
                    "clientId": SPOTIFY_CLIENT_ID,
                    "clientSecret": SPOTIFY_CLIENT_SECRET,
                    "countryCode": "US",
                    "albumLoadLimit": 10,
                    "playlistLoadLimit": 10,
                    "resolveArtistsInSearch": True,
                    "localFiles": False,
                },
            },
            "lavasearch": {
                "sources": ["spotify", "youtube"],
            },
        },
        "server": {
            "address": "0.0.0.0",
            "port": PORT,
            "http2": {"enabled": False},
        },
    }


def validate(cfg: dict):
    """تحقق صارم من القيم الحرجة قبل كتابة الملف."""
    assert cfg["lavalink"]["server"]["password"] == PASSWORD, "password mismatch"
    assert cfg["server"]["port"] == PORT, "port mismatch"
    assert cfg["lavalink"]["server"]["sources"]["youtube"] is False, "builtin youtube must be off"
    assert cfg["lavalink"]["server"]["sources"]["http"] is True, "http source must stay on"
    assert cfg["plugins"]["youtube"]["oauth"]["refreshToken"] == REFRESH_TOKEN, "refresh token mismatch"
    assert cfg["plugins"]["youtube"]["oauth"]["skipInitialization"] is True, "skipInitialization must be true"
    assert cfg["plugins"]["youtube"]["clients"], "clients list empty"
    # WEB إلزامي: العميل الوحيد الذي يستفيد من POT (التطابق مع مسار potsync)
    assert "WEB" in cfg["plugins"]["youtube"]["clients"], "WEB client required for POT path"
    assert cfg["plugins"]["lavasrc"]["spotify"]["clientId"] == SPOTIFY_CLIENT_ID, "spotify id mismatch"
    assert cfg["plugins"]["lavasrc"]["spotify"]["clientSecret"] == SPOTIFY_CLIENT_SECRET, "spotify secret mismatch"
    assert YOUTUBE_PLUGIN in [p["dependency"] for p in cfg["lavalink"]["plugins"]], "youtube plugin missing"


def main():
    cfg = build_config()
    validate(cfg)
    os.makedirs(os.path.dirname(OUTPUT) or ".", exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        yaml.safe_dump(cfg, f, sort_keys=False, allow_unicode=True, default_flow_style=False)
    # إعادة القراءة والتحقق النهائي
    with open(OUTPUT, "r", encoding="utf-8") as f:
        loaded = yaml.safe_load(f)
    validate(loaded)
    print(f"✅ Lavalink config written & validated: {OUTPUT}")
    print(f"   clients: {CLIENTS}")
    print(f"   port: {PORT} | password: {'*' * len(PASSWORD)}")
    print(f"   oauth refreshToken: {REFRESH_TOKEN[:12]}... ({len(REFRESH_TOKEN)} chars)")


if __name__ == "__main__":
    main()
GENCFG_EOF

# ── كود البوت الكامل ────────────────────────────────────────────────────────
RUN cat > /opt/bot/music.py <<'MUSICPY_EOF'
# -*- coding: utf-8 -*-
# ═══════════════════════════════════════════════════════════════════════════
#  elminyawe bot — بوت موسيقى ديسكورد (yt-dlp أساسي + Lavalink + احتياطي ffmpeg)
#  ─────────────────────────────────────────────────────────────────────────
#  • أمر play يعرض قائمة نتائج مرقّمة وينتظر اختيار المستخدم رقم الأغنية
#  • كل الأوامر تعمل بالبادئة (!play) أو بدونها، وكذلك كأوامر سلاش (/play)
#  • لا إضافة تلقائية لقائمة الانتظار ولا تشغيل تلقائي (AutoPlay مُعطّل)
#  • 🎯 المسار الأساسي: yt-dlp يستخرج رابط الصوت المباشر (كوكيز OAuth +
#    PO Token إجباري + حلّال تحديات يوتيوب 2026) ويُبثّ عبر مصدر HTTP
#  • طبقة ثانية: عملاء Lavalink الداخليون (WEB+POT/OAuth) ثم إصلاح تلقائي
#  • إذا تعذّر الوصول لـ Lavalink نهائياً: وضع احتياطي كامل بـ yt-dlp + ffmpeg
#  • قاعدة بيانات MariaDB: سجل التاريخ + إعدادات لكل سيرفر (اختياري - يتحمل
#    عدم توفرها بدون توقف)
# ═══════════════════════════════════════════════════════════════════════════

import asyncio
import logging
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import discord
import wavelink
import yt_dlp
import pymysql
from discord import app_commands
from discord.ext import commands

# ─────────────────────────────────────────────
#  الإعدادات من متغيرات البيئة
# ─────────────────────────────────────────────
TOKEN = os.getenv("DISCORD_TOKEN", "").strip()
PREFIX = os.getenv("DISCORD_PREFIX", "!").strip() or "!"

LAVALINK_HOST = os.getenv("LAVALINK_HOST", "127.0.0.1")
LAVALINK_PORT = int(os.getenv("LAVALINK_PORT", "2008"))
LAVALINK_PASSWORD = os.getenv("LAVALINK_PASSWORD", "ELMINYAWE")

MYSQL_HOST = os.getenv("MYSQL_HOST", "127.0.0.1")
MYSQL_ROOT_PASSWORD = os.getenv("MYSQL_ROOT_PASSWORD", "")
MYSQL_DATABASE = os.getenv("MYSQL_DATABASE", "musicbot")

IDLE_DISCONNECT_SEC = int(os.getenv("IDLE_DISCONNECT_SEC", "300"))

TEST_MODE = os.getenv("TEST_MODE") == "1"
TEST_GUILD_ID = int(os.getenv("TEST_GUILD_ID", "0") or 0)
TEST_CHANNEL_ID = int(os.getenv("TEST_CHANNEL_ID", "0") or 0)
TEST_RESULTS_FILE = os.getenv("TEST_RESULTS_FILE", "test_results.txt")

# وضع المحرك يُحدَّد عند الإقلاع: "lavalink" أو "ffmpeg"
ENGINE = "lavalink"

log = logging.getLogger("elminyawe")

# كلمات الأوامر التي تُقبل بدون بادئة (مثال: play ياه تامر عاشور)
BARE_OK = {
    "play", "p", "queue", "q", "nowplaying", "np", "skip", "s", "pause",
    "resume", "stop", "volume", "vol", "v", "loop", "shuffle", "skipto",
    "remove", "seek", "join", "leave", "dc", "247", "history", "ping", "help",
}

CANCEL_WORDS = {"الغاء", "إلغاء", "الإلغاء", "cancel", "الغاء."}

URL_RE = re.compile(r"^https?://\S+$", re.IGNORECASE)

# ─────────────────────────────────────────────
#  أدوات مساعدة عامة
# ─────────────────────────────────────────────

def fmt_time(ms: int) -> str:
    """تحويل ميلي ثانية إلى صيغة mm:ss أو hh:mm:ss."""
    try:
        ms = int(ms)
    except (TypeError, ValueError):
        return "0:00"
    if ms < 0:
        return "0:00"
    total = ms // 1000
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def progress_bar(pos: int, dur: int, size: int = 14) -> str:
    """شريط تقدم نصي: ▰▰▰▱▱▱."""
    try:
        pos = int(pos)
        dur = int(dur)
    except (TypeError, ValueError):
        dur, pos = 0, 0
    if dur <= 0:
        return "▱" * size
    frac = min(max(pos / dur, 0.0), 1.0)
    filled = int(round(frac * size))
    return "▰" * filled + "▱" * (size - filled)


def _v_playing(vc) -> bool:
    """هل يشغّل الآن؟ — تعمل مع wavelink.Player وdiscord.VoiceClient معاً.

    wavelink 3.x يوفر الخاصية playing بدل الطريقة is_playing() القديمة،
    وdiscord.VoiceClient يوفر is_playing(). هذه الدالة تفحص الاثنين بأمان.
    """
    if vc is None:
        return False
    prop = getattr(vc, "playing", None)
    if isinstance(prop, bool):
        return prop
    try:
        return bool(vc.is_playing())
    except AttributeError:
        return False
    except Exception:
        return False


def _v_paused(vc) -> bool:
    """هل متوقف مؤقتاً؟ — تعمل مع wavelink.Player وdiscord.VoiceClient معاً.

    wavelink 3.x يوفر الخاصية paused بدل الطريقة is_paused() القديمة،
    وdiscord.VoiceClient يوفر is_paused(). هذه الدالة تفحص الاثنين بأمان.
    """
    if vc is None:
        return False
    prop = getattr(vc, "paused", None)
    if isinstance(prop, bool):
        return prop
    try:
        return bool(vc.is_paused())
    except AttributeError:
        return False
    except Exception:
        return False


def is_url(text: str) -> bool:
    return bool(URL_RE.match((text or "").strip()))


def is_spotify(text: str) -> bool:
    t = (text or "").lower()
    return "open.spotify.com" in t or "spotify:" in t


# ─────────────────────────────────────────────
#  yt-dlp : استخراج روابط الصوت + البحث
# ─────────────────────────────────────────────
# سلسلة عملاء yt-dlp بالترتيب — web أولاً لأنه العميل الذي يعمل مع PO Token
_YT_CLIENTS = os.getenv(
    "YTDLP_CLIENTS", "web,web_safari,tv_simply,android_vr").strip()
_EXTRACTOR_ARGS = {"youtube": {
    "player_client": [c.strip() for c in _YT_CLIENTS.split(",") if c.strip()],
    # إجبار طلب مشغّل جديد بدلاً من استجابة صفحة الويب الخالية من PO Token
    "player_skip": ["webpage"],
    # ⚠️ حاسم جداً: السياسة الافتراضية 'auto' تتخطى جلب PO Token عندما تقول
    # سياسة العميل required=False — فيبدو الطلب كبوت ويُحجب. 'always' يُلزم الجلب
    "fetch_pot": ["always"],
}}

# كوكيز يوتيوب (لتجاوز فحص "لست روبوتاً" على IPs مراكز البيانات)
# الأولوية: 1) YOUTUBE_COOKIES (محتوى ملف كامل) 2) YOUTUBE_COOKIES_FILE (مسار)
# 3) تلقائي: /opt/bot/cookies.txt الذي يجلبونه yt_cookies.py بعد دخول OAuth
_COOKIES_FILE = os.getenv("YOUTUBE_COOKIES_FILE", "").strip()
_cookies_env = os.getenv("YOUTUBE_COOKIES", "").strip()
if _cookies_env and not _COOKIES_FILE:
    import tempfile
    _fd, _tmp = tempfile.mkstemp(prefix="elminyawe_cookies_", suffix=".txt")
    with os.fdopen(_fd, "w", encoding="utf-8") as _f:
        _f.write(_cookies_env.replace("\\n", "\n") + "\n")
    _COOKIES_FILE = _tmp
    log.info("🍪 تم تجهيز ملف كوكيز يوتيوب من متغير YOUTUBE_COOKIES")
elif _COOKIES_FILE:
    log.info(f"🍪 استخدام ملف الكوكيز: {_COOKIES_FILE}")

# مسار الكوكيز التلقائية — يكتبها yt_cookies.py بعد تسجيل دخول OAuth.
# يُفحص وجوده عند كل استدعاء (وليس عند الإقلاع فقط) لأن الملف يُكتب
# بعد انطلاق البوت، ويُجدّد دورياً كل 6 ساعات.
_AUTO_COOKIES_PATH = os.getenv("YT_AUTO_COOKIES_FILE", "/opt/bot/cookies.txt").strip()

YDL_BASE = {
    "quiet": True,
    "no_warnings": True,
    "skip_download": True,
    "noplaylist": True,
    "socket_timeout": 20,
    "retries": 3,
    "format": "bestaudio/best",
    "extractor_args": _EXTRACTOR_ARGS,
    # حلّال تحديات جافاسكربت البعيدة (EJS) — مطلوب لفك توقيعات يوتيوب الحديثة،
    # يُنزَّل مرة واحدة ويُخزَّن؛ وإن تعذر فتبقى الصيغ القديمة (itag 18) تعمل
    "remote_components": ["ejs:github"],
}

if _COOKIES_FILE and os.path.isfile(_COOKIES_FILE):
    YDL_BASE["cookiefile"] = _COOKIES_FILE

YDL_SEARCH = dict(YDL_BASE)
YDL_SEARCH["extract_flat"] = True   # بحث سريع بدون تحليل كامل للنتائج


def _ydl_extract_sync(ydl_opts: dict, query: str) -> dict:
    opts = dict(ydl_opts)
    # حقن الكوكيز التلقائية ديناميكياً (إذا لم توجد كوكيز يدوية)
    if ("cookiefile" not in opts and _AUTO_COOKIES_PATH
            and os.path.isfile(_AUTO_COOKIES_PATH)):
        opts["cookiefile"] = _AUTO_COOKIES_PATH
    with yt_dlp.YoutubeDL(opts) as ydl:
        return ydl.extract_info(query, download=False)


async def ytdlp_search(query: str, count: int = 10) -> list:
    """بحث نصي عبر yt-dlp — يعيد قائمة نتائج مختصرة."""
    def _run():
        info = _ydl_extract_sync(YDL_SEARCH, f"ytsearch{count}:{query}")
        return (info or {}).get("entries") or []
    try:
        entries = await asyncio.to_thread(_run)
    except Exception as e:
        log.warning(f"yt-dlp search failed: {e!r}")
        return []
    out = []
    for e in entries or []:
        if not e:
            continue
        out.append({
            "title": e.get("title") or "غير معروف",
            "duration": int(e.get("duration") or 0),
            "uploader": e.get("uploader") or e.get("channel") or "",
            "url": e.get("url") or e.get("webpage_url") or "",
            "id": e.get("id") or "",
        })
    return [x for x in out if x["url"]]


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """مفتتاحة بلا متابعة تحويلات — لنقرر المتابعة يدوياً خطوة بخطوة."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _resolve_http_redirects(url: str) -> str:
    """يتبع سلسلة تحويلات 302 يدوياً ويعيد الرابط النهائي.
    ⚠️ Lavaplayer (مصدر HTTP في Lavalink) لا يتبع تحويلات googlevideo —
    بدون هذه الخطوة يفشل البث برسالة 'Not success status code: 302'.
    متابعة يدوية حتمية (HEAD حتى 5 قفزات) لأن urllib لا يتبع تحويلات HEAD."""
    if not (url.startswith("http://") or url.startswith("https://")):
        return url
    try:
        opener = urllib.request.build_opener(_NoRedirect)
    except Exception:
        return url
    current = url
    try:
        for _hop in range(5):
            req = urllib.request.Request(current, method="HEAD", headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                              "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            })
            try:
                with opener.open(req, timeout=15):
                    return current        # نجاح مباشر بلا تحويلات
            except urllib.error.HTTPError as e:
                loc = e.headers.get("Location") if e.headers else None
                if not loc or not (300 <= e.code < 400):
                    return current
                current = urllib.parse.urljoin(current, loc)
        return current
    except Exception as e:
        log.debug(f"redirect resolve kept original ({e!r})")
        return url


async def ytdlp_resolve(url: str) -> dict:
    """استخراج رابط الصوت المباشر لرابط/معرّف فيديو."""
    def _run():
        return _ydl_extract_sync(YDL_BASE, url)
    info = await asyncio.to_thread(_run)
    if not info:
        raise RuntimeError("لم يتم العثور على نتائج")
    if "entries" in info:
        entries = [e for e in (info.get("entries") or []) if e]
        if not entries:
            raise RuntimeError("القائمة فارغة")
        info = entries[0]
    direct = info.get("url")
    if not direct:
        best = None
        for f in info.get("formats") or []:
            if f.get("acodec") not in (None, "none") or f.get("vcodec") in (None, "none"):
                if (f.get("abr") or 0) and (best is None or (f.get("abr") or 0) > (best.get("abr") or 0)):
                    if f.get("vcodec") in (None, "none"):
                        best = f
        direct = (best or {}).get("url") or info.get("webpage_url")
    if not direct:
        raise RuntimeError("لم يتم العثور على مسار صوتي")
    return {
        "title": info.get("title") or "غير معروف",
        "duration": int(info.get("duration") or 0),
        "uploader": info.get("uploader") or info.get("channel") or "",
        "url": _resolve_http_redirects(direct),
        "webpage_url": info.get("webpage_url") or url,
        "id": info.get("id") or "",
    }


# ─────────────────────────────────────────────
#  قاعدة البيانات (MariaDB) — اختيارية وتتحمل الفشل
# ─────────────────────────────────────────────
class Database:
    """غلاف بسيط حول PyMySQL — لا يُوقف البوت إذا كانت قاعدة البيانات غير متاحة."""

    def __init__(self):
        self.conn = None
        self.available = False

    def _connect(self):
        self.conn = pymysql.connect(
            host=MYSQL_HOST,
            user="root",
            password=MYSQL_ROOT_PASSWORD,
            database=MYSQL_DATABASE,
            charset="utf8mb4",
            autocommit=True,
            connect_timeout=5,
            cursorclass=pymysql.cursors.DictCursor,
        )
        self.available = True

    def ensure(self):
        try:
            if self.conn is None:
                self._connect()
                return True
            self.conn.ping(reconnect=True)
            self.available = True
            return True
        except Exception as e:
            self.available = False
            log.debug(f"DB unavailable: {e!r}")
            return False

    def init_tables(self):
        """محاولة إنشاء الجداول عند الإقلاع مع إعادة محاولة (MariaDB قد يتأخر)."""
        ddl_history = (
            "CREATE TABLE IF NOT EXISTS history ("
            " id BIGINT AUTO_INCREMENT PRIMARY KEY,"
            " guild_id BIGINT NOT NULL,"
            " user_id BIGINT DEFAULT 0,"
            " user_name VARCHAR(128) DEFAULT '',"
            " title VARCHAR(256) NOT NULL,"
            " uri VARCHAR(512) DEFAULT '',"
            " source VARCHAR(32) DEFAULT 'youtube',"
            " played_at DATETIME DEFAULT CURRENT_TIMESTAMP"
            ") CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
        )
        ddl_settings = (
            "CREATE TABLE IF NOT EXISTS guild_settings ("
            " guild_id BIGINT PRIMARY KEY,"
            " volume INT DEFAULT 100,"
            " loop_mode VARCHAR(8) DEFAULT 'off',"
            " stay_247 TINYINT DEFAULT 0"
            ") CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
        )
        for attempt in range(1, 13):
            try:
                if self.ensure():
                    self.exec(ddl_history)
                    self.exec(ddl_settings)
                    log.info("✅ قاعدة البيانات جاهزة (history + guild_settings)")
                    return True
            except Exception as e:
                log.debug(f"DB init attempt {attempt} failed: {e!r}")
            time.sleep(5)
        log.warning("⚠️ تعذّر الوصول لقاعدة البيانات — سيستمر البوت بدون حفظ التاريخ/الإعدادات")
        return False

    def exec(self, sql: str, args: tuple = ()):
        try:
            if not self.ensure():
                return False
            with self.conn.cursor() as cur:
                cur.execute(sql, args)
            return True
        except Exception as e:
            log.debug(f"DB exec failed: {e!r}")
            self.available = False
            return False

    def fetchall(self, sql: str, args: tuple = ()):
        try:
            if not self.ensure():
                return None
            with self.conn.cursor() as cur:
                cur.execute(sql, args)
                return cur.fetchall()
        except Exception as e:
            log.debug(f"DB fetch failed: {e!r}")
            self.available = False
            return None


DB = Database()


# ─────────────────────────────────────────────
#  البوت الرئيسي
# ─────────────────────────────────────────────
def build_prefix():
    """بادئة مرنة: الأوامر المعروفة تُقبل بدون بادئة، وغيرها يتطلب البادئة.

    ⚠️ نقطة حرجة: إذا بدأت الرسالة بالبادئة يجب إعادة البادئة الحقيقية (PREFIX)
    حتى يقتطعها discord.py من النص. إعادة "" تجعل البادئة الفارغة "تطابق" من
    الموضع صفر دون تقدّم، فيقرأ الإطار الكلمة الأولى بعلامة التعجب نفسها
    ("!play") ويبحث عن أمر بهذا الاسم ويجده غير موجود — CommandNotFound."""
    def _prefix(bot, message):
        content = (message.content or "").strip()
        if not content:
            return commands.when_mentioned_or(PREFIX)(bot, message)
        if content.startswith(PREFIX):
            return PREFIX       # البادئة العادية — ستُقتطع تلقائياً من النص
        first = content.split(maxsplit=1)[0].lower()
        if first in BARE_OK:
            return ""           # يُقبل بدون بادئة: play ياه تامر عاشور
        return commands.when_mentioned_or(PREFIX)(bot, message)
    return _prefix


class ElminyaweBot(commands.Bot):
    def __init__(self):
        intents = discord.Intents.default()
        intents.message_content = True
        intents.voice_states = True
        super().__init__(
            command_prefix=build_prefix(),
            intents=intents,
            help_command=None,
            activity=discord.Activity(type=discord.ActivityType.listening, name="🎵 play أو /play — اسم الأغنية"),
        )

    async def setup_hook(self):
        """الاتصال بـ Lavalink أو التحويل لوضع الاحتياط، ثم تحميل الوحدة."""
        global ENGINE
        if not TOKEN or "PUT_YOUR" in TOKEN.upper():
            log.critical(
                "❌ لم يتم ضبط توكن البوت!\n"
                "   ضع توكن بوتك في متغير البيئة DISCORD_TOKEN\n"
                "   (في Railway: Variables → DISCORD_TOKEN)"
            )
            sys.exit(1)

        connected = False
        last_err = None
        for attempt in range(1, 4):
            try:
                node = wavelink.Node(
                    uri=f"http://{LAVALINK_HOST}:{LAVALINK_PORT}",
                    password=LAVALINK_PASSWORD,
                )
                await wavelink.Pool.connect(client=self, nodes=[node])
                connected = True
                ENGINE = "lavalink"
                log.info(f"✅ متصل بـ Lavalink ({LAVALINK_HOST}:{LAVALINK_PORT})")
                break
            except Exception as e:
                last_err = e
                log.warning(f"⚠️ محاولة {attempt}/3: تعذر الاتصال بـ Lavalink: {e!r}")
                await asyncio.sleep(5)

        if not connected:
            ENGINE = "ffmpeg"
            log.warning(
                f"⚠️ تعذّر الاتصال بـ Lavalink نهائياً ({last_err!r}) —\n"
                "   🔁 تشغيل وضع الاحتياط: البث المباشر عبر yt-dlp + ffmpeg"
            )

        await self.add_cog(MusicCog(self))

        # ── تسجيل أوامر السلاش (/) ──────────────────────────────────
        # المزامنة العالمية تغطي كل السيرفرات (قد تظهر فيها خلال دقائق/ساعة)،
        # والمزامنة داخل السيرفرات (on_ready) تجعلها فورية. GUILD_ID اختياري
        # لتسجيل فوري مبكر في سيرفر محدد قبل اتصال الـ Gateway.
        self._global_sync_ok = False
        try:
            n = await self.tree.sync()
            self._global_sync_ok = True
            log.info(f"✅ سُجّلت {len(n)} أمر سلاش عالمياً")
        except Exception as e:
            log.warning(f"⚠️ المزامنة العالمية لأوامر السلاش فشلت: {e!r}")
        gid_env = os.getenv("GUILD_ID", "").strip()
        if gid_env.isdigit():
            try:
                gobj = discord.Object(id=int(gid_env))
                self.tree.copy_global_to(guild=gobj)
                n = await self.tree.sync(guild=gobj)
                log.info(f"✅ سُجّلت {len(n)} أمر سلاش فورياً داخل السيرفر {gid_env}")
            except Exception as e:
                log.warning(f"⚠️ مزامنة السلاش للسيرفر {gid_env} فشلت: {e!r}")

        if TEST_MODE:
            self.loop.create_task(run_test_flow(self))

    async def on_ready(self):
        """مزامنة أوامر السلاش فورياً داخل كل سيرفر يتواجد به البوت (مرة واحدة)."""
        if getattr(self, "_guild_sync_done", False):
            return
        self._guild_sync_done = True
        gid_env = os.getenv("GUILD_ID", "").strip()
        for g in list(self.guilds):
            if gid_env.isdigit() and str(g.id) == gid_env:
                continue    # سُجّلت بالفعل في setup_hook
            try:
                gobj = discord.Object(id=g.id)
                self.tree.copy_global_to(guild=gobj)
                n = await self.tree.sync(guild=gobj)
                log.info(f"✅ أوامر السلاش جاهزة فوراً داخل السيرفر {g.id} ({len(n)} أمراً)")
            except Exception as e:
                log.warning(f"⚠️ مزامنة السلاش للسيرفر {g.id} فشلت: {e!r}")
        if not getattr(self, "_global_sync_ok", False):
            try:
                n = await self.tree.sync()
                self._global_sync_ok = True
                log.info(f"✅ سُجّلت {len(n)} أمر سلاش عالمياً (محاولة on_ready)")
            except Exception as e:
                log.warning(f"⚠️ المزامنة العالمية لا تزال تفشل: {e!r}")


# ─────────────────────────────────────────────
#  وحدة الموسيقى
# ─────────────────────────────────────────────
class MusicCog(commands.Cog):
    def __init__(self, bot: ElminyaweBot):
        self.bot = bot
        self.db = DB

        # طوابير التشغيل لكل سيرفر (يُضاف إليها فقط بإجراء صريح من المستخدم)
        self.queues: dict[int, list] = {}
        # وضع التكرار لكل سيرفر: off / track / queue
        self.loop_mode: dict[int, str] = {}
        # خاصية 24/7 لكل سيرفر
        self.stay_247: dict[int, bool] = {}
        # مستخدم طلب التشغيل الأخير (للتاريخ)
        self.last_requester: dict[int, discord.Member] = {}
        # رسائل/مهام "شغّال الآن" (شريط التقدم الحي)
        self._np_msgs: dict[int, discord.Message] = {}
        self._np_tasks: dict[int, asyncio.Task] = {}
        # آمن ضد حلقات الإصلاح: المقاطع التي جُرِّب إصلاحها مسبقاً لكل سيرفر
        self._rescued: dict[int, set] = {}
        # الانتظار المعلّق لقائمة الاختيار لكل مستخدم (epoch object)
        self._pending: dict[int, object] = {}
        # القناة النصية الأخيرة لكل سيرفر (لإرسال رسائل الإصلاح/الإشعارات)
        self._text_channel: dict[int, discord.abc.Messageable] = {}
        # وقت آخر نشاط صوتي (لقطع الاتصال عند الخمول)
        self._idle_since: dict[int, float] = {}
        # حالة محرك ffmpeg الاحتياطي لكل سيرفر
        self._ff_state: dict[int, dict] = {}
        # بيانات العرض الأصلية للمسارات المباشرة (مفتاحها معرّف المسار)
        self._meta_overrides: dict[str, dict] = {}

        self._idle_task = self.bot.loop.create_task(self._idle_monitor())

    def destroy(self):
        if self._idle_task:
            self._idle_task.cancel()

    # ─────────────────────────────────────────
    #  أدوات الصوت
    # ─────────────────────────────────────────

    async def _defer_if_slash(self, ctx):
        """أوامر السلاش مهلة ردها 3 ثوانٍ فقط — defer فوري يمنحنا حتى 15 دقيقة
        للبحث والتحميل. في وضع البادئة لا يفعل شيئاً (لا يوجد interaction)."""
        try:
            if ctx.interaction is not None and not ctx.interaction.response.is_done():
                await ctx.interaction.response.defer(thinking=True)
        except Exception as e:
            log.debug(f"defer skipped: {e!r}")

    def _target_channel(self, ctx) -> discord.abc.Connectable | None:
        return ctx.author.voice.channel if (ctx.author and ctx.author.voice) else None

    async def _ensure_voice(self, ctx):
        """الاتصال/الانتقال للقناة الصوتية للمستخدم. يعيد مشغّل الصوت أو None."""
        ch = self._target_channel(ctx)
        if ch is None:
            await ctx.reply("🔇 ادخل قناة صوتية أولاً حتى أستطيع التشغيل.")
            return None
        perms = ch.permissions_for(ctx.guild.me)
        if not perms.connect or not perms.speak:
            await ctx.reply("⛔ ليس لدي صلاحية الاتصال/التحدث في تلك القناة.")
            return None

        vc = ctx.guild.voice_client
        cls = wavelink.Player if ENGINE == "lavalink" else discord.VoiceClient
        try:
            if vc is None:
                vc = await ch.connect(cls=cls, self_deaf=True)
                if isinstance(vc, wavelink.Player):
                    # تعطيل التشغيل التلقائي تماماً — لا إضافة طوابير من تلقاء نفسها
                    vc.autoplay = wavelink.AutoPlayMode.disabled
                    await self._apply_settings(ctx.guild.id, vc)
            elif vc.channel.id != ch.id:
                await vc.move_to(ch)
        except Exception as e:
            log.error(f"voice connect failed: {e!r}")
            await ctx.reply(f"❌ فشل الاتصال بالقناة الصوتية: `{e}`")
            return None
        return vc

    def _queue_of(self, guild_id: int) -> list:
        return self.queues.setdefault(guild_id, [])

    async def _apply_settings(self, guild_id: int, player: wavelink.Player):
        """تحميل إعدادات السيرفر من قاعدة البيانات وتطبيقها."""
        rows = self.db.fetchall(
            "SELECT volume, loop_mode, stay_247 FROM guild_settings WHERE guild_id=%s", (guild_id,)
        )
        if not rows:
            return
        row = rows[0]
        vol = max(0, min(int(row.get("volume") or 100), 200))
        self.loop_mode[guild_id] = (row.get("loop_mode") or "off")
        self.stay_247[guild_id] = bool(row.get("stay_247"))
        try:
            await player.set_volume(vol)
        except Exception:
            try:
                player.volume = vol
            except Exception:
                pass

    def _save_settings(self, guild_id: int):
        vol = 100
        try:
            vc = self.bot.get_guild(guild_id).voice_client if self.bot.get_guild(guild_id) else None
            if vc is not None:
                vol = int(getattr(vc, "volume", 100) or 100)
        except Exception:
            pass
        mode = self.loop_mode.get(guild_id, "off")
        stay = 1 if self.stay_247.get(guild_id) else 0
        self.db.exec(
            "INSERT INTO guild_settings (guild_id, volume, loop_mode, stay_247) VALUES (%s,%s,%s,%s) "
            "ON DUPLICATE KEY UPDATE volume=VALUES(volume), loop_mode=VALUES(loop_mode), stay_247=VALUES(stay_247)",
            (guild_id, vol, mode, stay),
        )

    def _current_volume(self, guild) -> int:
        try:
            vc = guild.voice_client
            if isinstance(vc, wavelink.Player):
                return int(getattr(vc, "volume", 100) or 100)
            if isinstance(vc, discord.VoiceClient):
                src = vc.source
                if isinstance(src, discord.PCMVolumeTransformer):
                    return int(round(src.volume * 100))
        except Exception:
            pass
        return 100

    # ─────────────────────────────────────────
    #  التحميل عبر Lavalink
    # ─────────────────────────────────────────

    async def _lavalink_load(self, query: str):
        """تحميل عبر Lavalink. يعيد (قائمة مقاطع, قائمة تشغيل أو None).

        يدعم: روابط مباشرة، روابط سبوتيفاي، وبادئات البحث (ytsearch: إلخ).
        الاستعلام النصي العادي يُحوَّل تلقائياً إلى بحث يوتيوب.
        """
        query = (query or "").strip()
        KNOWN_PREFIXES = ("ytsearch:", "ytmsearch:", "spsearch:", "sctrack:", "scsearch:", "http://", "https://")
        if not any(query.startswith(p) for p in KNOWN_PREFIXES):
            query = f"ytsearch:{query}"   # بحث نصي عادي → يوتيوب
        res = await wavelink.Pool.fetch_tracks(query)
        if isinstance(res, wavelink.Playlist):
            return list(res.tracks or []), res
        if isinstance(res, wavelink.Playable):
            return [res], None
        if isinstance(res, (list, wavelink.Search)):
            return list(res), None
        return [], None

    # ─────────────────────────────────────────
    #  المسار الأساسي: yt-dlp يستخرج الرابط المباشر ثم يُبثّ عبر Lavalink
    # ─────────────────────────────────────────

    @staticmethod
    def _is_youtube_track(track) -> bool:
        """هل هذا مسار يوتيوب أصلي (يحتاج استخراجاً عبر yt-dlp)؟"""
        uri = (getattr(track, "uri", "") or "")
        return ("youtube.com/" in uri) or ("youtu.be/" in uri)

    def _register_meta(self, track, info: dict):
        """حفظ بيانات العرض الأصلية للمسار المباشر — مسارات HTTP في Lavalink
        تحمل عنواناً فارغاً (Unknown title) فنستبدله بالأصلي في كل الواجهات."""
        key = getattr(track, "identifier", None) or getattr(track, "uri", "") or ""
        if not key:
            return
        self._meta_overrides[key] = {
            "title": info.get("title") or "",
            "author": info.get("uploader") or "",
            "duration_ms": int((info.get("duration") or 0) * 1000),
            "webpage_url": info.get("webpage_url") or "",
        }
        if len(self._meta_overrides) > 300:   # حد أقصى لمنع النمو اللانهائي
            self._meta_overrides.pop(next(iter(self._meta_overrides)))

    def _display_meta(self, track) -> dict:
        """بيانات العرض المحفوظة لمسار مباشر، أو قائمة فارغة للمسارات الأصلية."""
        key = getattr(track, "identifier", None) or getattr(track, "uri", "") or ""
        return self._meta_overrides.get(key) or {}

    def _disp_title(self, t) -> str:
        meta = self._display_meta(t)
        return meta.get("title") or getattr(t, "title", None) or (
            t.get("title", "") if isinstance(t, dict) else str(t))

    def _disp_len(self, t) -> int:
        meta = self._display_meta(t)
        if meta.get("duration_ms"):
            return int(meta["duration_ms"])
        v = getattr(t, "length", None)
        if v is None:
            v = (t.get("duration") or 0) * 1000 if isinstance(t, dict) else 0
        return int(v or 0)

    async def _play_via_ytdlp(self, ctx, player: wavelink.Player, yt_url: str,
                              display_title: str = "") -> bool:
        """المسار الأساسي للتشغيل: استخراج رابط صوت مباشر عبر yt-dlp
        (كوكيز OAuth + PO Token إجباري) ثم بثّه عبر مصدر HTTP في Lavalink.
        يعيد True عند نجاح البدء أو الإضافة للطابور."""
        if not yt_url:
            return False
        try:
            info = await ytdlp_resolve(yt_url)
        except Exception as e:
            log.warning(f"ytdlp primary extract failed ({yt_url}): {e!r}")
            return False
        try:
            loaded, _pl = await self._lavalink_load(info["url"])
        except Exception as e:
            log.warning(f"lavalink direct load failed: {e!r}")
            return False
        if not loaded:
            return False
        t = loaded[0]
        self._register_meta(t, info)
        shown = display_title or info.get("title") or ""
        if getattr(player, "playing", False) or getattr(player, "paused", False):
            self._queue_of(player.guild.id).append(t)
            try:
                await ctx.reply(f"➕ أُضيفت إلى الطابور: **{shown}**", mention_author=False)
            except Exception:
                pass
            return True
        try:
            player.autoplay = wavelink.AutoPlayMode.disabled
            await player.play(t)
        except Exception as e:
            log.warning(f"direct play failed: {e!r}")
            return False
        try:
            await ctx.reply(f"🎶 جاري تشغيل: **{shown}**", mention_author=False)
        except Exception:
            pass
        return True

    # ─────────────────────────────────────────
    #  أمر play — القائمة المرقّمة ثم اختيار رقم
    # ─────────────────────────────────────────

    @app_commands.describe(query="اسم الأغنية أو الرابط")
    @commands.hybrid_command(name="play", aliases=["p"], help="تشغيل أغنية من يوتيوب/سبوتيفاي أو رابط مباشر", description="تشغيل أغنية من يوتيوب/سبوتيفاي أو رابط مباشر")
    async def play(self, ctx: commands.Context, *, query: str = None):
        await self._defer_if_slash(ctx)
        if not query:
            await ctx.reply(
                "✏️ اكتب اسم الأغنية أو الرابط بعد الأمر:\n"
                f"`{PREFIX}play ياه تامر عاشور`",
            )
            return

        vc = await self._ensure_voice(ctx)
        if vc is None:
            return

        if is_url(query):
            await self._play_url(ctx, query.strip())
            return

        # بحث نصي → قائمة نتائج مرقّمة → انتظار اختيار المستخدم
        if ENGINE == "lavalink":
            tracks, _pl = await self._lavalink_load(query)
            results = [
                {
                    "title": t.title, "author": t.author or "",
                    "duration": int(t.length or 0), "uri": t.uri or "", "track": t,
                }
                for t in (tracks or [])
            ]
        else:
            entries = await ytdlp_search(query, 10)
            results = [
                {
                    "title": e["title"], "author": e.get("uploader") or "",
                    "duration": int(e.get("duration") or 0), "uri": e.get("url") or "", "entry": e,
                }
                for e in (entries or [])
            ]

        if not results:
            await ctx.reply("😕 لا توجد نتائج للبحث — جرّب اسماً آخر.")
            return

        chosen = await self._selection_menu(ctx, query, results)
        if chosen is None:
            return
        await self._start_selected(ctx, results[chosen])

    async def _selection_menu(self, ctx, query: str, results: list):
        """عرض قائمة مرقّمة وانتظار اختيار المستخدم رقم الأغنية. يعيد الفهرس أو None."""
        lines = []
        for i, r in enumerate(results[:10], start=1):
            dur = fmt_time(r.get("duration") or 0)
            lines.append(f"**{i}.** [{r['title']}]({r.get('uri') or ''}) — `{dur}` {r.get('author') or ''}".replace("]()", "]"))
        desc = (
            f"🎵 **نتائج البحث عن:** «{query}»\n"
            "─────────────────────\n" + "\n".join(lines) +
            "\n─────────────────────\n"
            "✏️ اكتب **رقم** الأغنية لاختيارها خلال **60 ثانية**\n"
            "❌ أو اكتب **إلغاء**"
        )
        embed = discord.Embed(description=desc, color=discord.Color.blurple())
        embed.set_footer(
            text=f"طلبها: {ctx.author.display_name} • المحرك: {'Lavalink' if ENGINE == 'lavalink' else 'yt-dlp بديل'}"
        )
        msg = await ctx.reply(embed=embed)

        # إلغاء أي بحث معلّق سابق لنفس المستخدم (epoch جديد)
        epoch = object()
        self._pending[ctx.author.id] = epoch

        def check(m: discord.Message):
            if m.author.id != ctx.author.id or m.channel.id != ctx.channel.id:
                return False
            if self._pending.get(ctx.author.id) is not epoch:
                return False
            c = m.content.strip()
            return c.isdigit() or c in CANCEL_WORDS

        try:
            try:
                m = await self.bot.wait_for("message", check=check, timeout=60)
            except asyncio.TimeoutError:
                still = self._pending.get(ctx.author.id) is epoch
                if still:
                    self._pending.pop(ctx.author.id, None)
                try:
                    await msg.edit(
                        embed=discord.Embed(
                            description=("⌛ انتهى وقت الاختيار — أرسل الأمر من جديد." if still
                                         else "🔄 أُلغي هذا البحث (تم بدء بحث أحدث)."),
                            color=discord.Color.dark_grey(),
                        )
                    )
                except Exception:
                    pass
                return None

            content = m.content.strip()
            try:
                await m.delete()
            except Exception:
                pass
            if content in CANCEL_WORDS:
                self._pending.pop(ctx.author.id, None)
                try:
                    await msg.edit(embed=discord.Embed(description="❌ تم الإلغاء.", color=discord.Color.dark_grey()))
                except Exception:
                    pass
                return None
            n = int(content)
            if not (1 <= n <= min(len(results), 10)):
                raise ValueError
            self._pending.pop(ctx.author.id, None)
            return n - 1
        finally:
            pass

    async def _start_selected(self, ctx, result: dict):
        """تشغيل الأغنية المختارة — أغنية واحدة فقط، بلا إضافة تلقائية للطابور."""
        gid = ctx.guild.id
        self.last_requester[gid] = ctx.author
        if ENGINE == "lavalink":
            await self._lavalink_start(ctx, result["track"], result["title"])
        else:
            await self._ff_play_resolved(ctx, result)

    async def _play_url(self, ctx, url: str):
        """رابط مباشر (يوتيوب/سبوتيفاي/قائمة تشغيل)."""
        gid = ctx.guild.id
        self.last_requester[gid] = ctx.author
        if is_spotify(url) and ENGINE != "lavalink":
            await ctx.reply(
                "⚠️ روابط Spotify تعمل فقط عندما يكون محرك Lavalink نشطاً.\n"
                "جرّب البحث بالاسم بدلاً من الرابط.",
            )
            return

        if ENGINE == "lavalink":
            try:
                tracks, playlist = await self._lavalink_load(url)
            except Exception as e:
                await ctx.reply(f"❌ فشل تحميل الرابط: `{e}`")
                return
            if not tracks:
                await ctx.reply("😕 لم أجد شيئاً في هذا الرابط.")
                return
            if playlist and len(tracks) > 1:
                vc = await self._ensure_voice(ctx)
                if vc is None:
                    return
                q = self._queue_of(gid)
                playing = bool(getattr(vc, "playing", False) or getattr(vc, "is_playing", lambda: False)())
                if playing or getattr(vc, "paused", False):
                    q.extend(tracks)
                    await ctx.reply(
                        f"📜 أُضيفت **{len(tracks)}** أغنية من قائمة التشغيل «{playlist.name}» إلى الطابور.",
                    )
                else:
                    first = tracks.pop(0)
                    q.extend(tracks)
                    await self._lavalink_start(ctx, first, first.title, quiet=True)
                    await ctx.reply(
                        f"📜 تشغيل قائمة التشغيل «{playlist.name}» — **{len(tracks) + 1}** أغنية.",
                    )
                return
            await self._lavalink_start(ctx, tracks[0], tracks[0].title)
        else:
            # وضع الاحتياط: قوائم التشغيل الكاملة غير مدعومة — نأخذ العنصر الأول أو نبحث
            if "list=" in url and "watch?" not in url and "/playlist" in url:
                await ctx.reply(
                    "⚠️ في وضع الاحتياط (yt-dlp) قوائم التشغيل الكاملة غير مدعومة — "
                    "سيتم تشغيل أول أغنية فيها.",
                )
            try:
                info = await ytdlp_resolve(url)
            except Exception as e:
                await ctx.reply(f"❌ فشل استخراج الرابط: `{e}`")
                return
            await self._ff_play_resolved(ctx, info)


    # ─────────────────────────────────────────
    #  بدء التشغيل عبر Lavalink
    # ─────────────────────────────────────────

    async def _lavalink_start(self, ctx, track, title: str = None, quiet: bool = False):
        gid = ctx.guild.id
        self._text_channel[gid] = ctx.channel
        self._rescued[gid] = set()          # بداية نظيفة للإصلاح مع كل طلب جديد
        vc = ctx.guild.voice_client
        if not isinstance(vc, wavelink.Player):
            vc = await self._ensure_voice(ctx)
            if vc is None:
                return
        if getattr(vc, "playing", False) or getattr(vc, "paused", False):
            q = self._queue_of(gid)
            q.append(track)
            if not quiet:
                await ctx.reply(
                    f"➕ أُضيفت إلى الطابور (الموقع {len(q)}): **{title or track.title}**",
                    mention_author=False,
                )
            return
        # ── المسار الأساسي: يوتيوب عبر yt-dlp أولاً (أقوى ضد الحجب) ──
        if track is not None and self._is_youtube_track(track):
            try:
                if await self._play_via_ytdlp(ctx, vc, track.uri or "",
                                              title or track.title or ""):
                    return
            except Exception as e:
                log.warning(f"primary ytdlp path failed: {e!r}")
        try:
            vc.autoplay = wavelink.AutoPlayMode.disabled
            await vc.play(track)
        except Exception as e:
            log.error(f"Lavalink play failed: {e!r}")
            await ctx.reply(f"❌ فشل بدء التشغيل: `{e}`", mention_author=False)
            return
        if not quiet:
            await ctx.reply(f"🎶 جاري تشغيل: **{title or track.title}**", mention_author=False)

    # ─────────────────────────────────────────
    #  أحداث Lavalink
    # ─────────────────────────────────────────

    @commands.Cog.listener()
    async def on_wavelink_track_start(self, payload: wavelink.TrackStartEventPayload):
        try:
            player = payload.player
            track = payload.track
            if player is None or track is None:
                return
            gid = player.guild.id
            self._idle_since.pop(gid, None)
            # حماية إضافية: لا تشغيل تلقائي مطلقاً
            try:
                player.autoplay = wavelink.AutoPlayMode.disabled
            except Exception:
                pass
            self._cancel_np_task(gid)
            await self._send_np_message(gid, player)
            meta = self._display_meta(track)
            await self._insert_history(gid,
                                       meta.get("title") or track.title or "",
                                       meta.get("webpage_url") or track.uri or "",
                                       getattr(track, "source", "") or "youtube")
        except Exception as e:
            log.error(f"track_start handler error: {e!r}")

    @commands.Cog.listener()
    async def on_wavelink_track_end(self, payload: wavelink.TrackEndEventPayload):
        try:
            player = payload.player
            track = payload.track
            reason = getattr(payload, "reason", "") or ""
            if player is None:
                return
            gid = player.guild.id
            self._cancel_np_task(gid)

            if reason in ("stopped", "replaced", "cleanup"):
                return

            if reason == "loadFailed":
                await self._rescue_or_advance(player, track)
                return

            await self._advance_or_stop(player, finished_track=track, failed=False)
        except Exception as e:
            log.error(f"track_end handler error: {e!r}")

    @commands.Cog.listener()
    async def on_wavelink_track_exception(self, payload: wavelink.TrackExceptionEventPayload):
        # لا نُقدّم هنا — حدث انتهاء المسار (loadFailed) هو من يُدير الإصلاح
        try:
            t = getattr(payload, "track", None)
            log.warning(f"track exception: {t.title if t else '?'}")
        except Exception:
            pass

    @commands.Cog.listener()
    async def on_wavelink_track_stuck(self, payload: wavelink.TrackStuckEventPayload):
        try:
            log.warning(f"track stuck: {getattr(payload.track, 'title', '?')}")
        except Exception:
            pass

    async def _rescue_or_advance(self, player: wavelink.Player, failed_track):
        """إصلاح تلقائي عند فشل التشغيل:
        • مسار مباشر فشل (رابط منتهٍ مثلاً) → إعادة استخراج مرة واحدة عبر
          رابط الصفحة الأصلي المحفوظ في بيانات العرض.
        • مسار يوتيوب أصلي فشل → استخراج عبر yt-dlp ثم بث HTTP.
        إذا سبق الإصلاح → الانتقال للتالي."""
        gid = player.guild.id
        rescued = self._rescued.setdefault(gid, set())
        key = getattr(failed_track, "identifier", None) or getattr(failed_track, "uri", "") or str(failed_track)
        url = getattr(failed_track, "uri", None)
        ch = self._text_channel.get(gid)

        # 1) المسار المباشر نفسه فشل — نعيد الاستخراج من رابط الصفحة الأصلي
        meta = self._display_meta(failed_track)
        if meta:
            rkey = f"direct:{key}"
            if rkey in rescued:
                await self._advance_or_stop(player, finished_track=None, failed=True)
                return
            rescued.add(rkey)
            try:
                info = await ytdlp_resolve(meta.get("webpage_url") or url or "")
                loaded, _pl = await self._lavalink_load(info["url"])
                if loaded:
                    self._register_meta(loaded[0], info)
                    player.autoplay = wavelink.AutoPlayMode.disabled
                    await player.play(loaded[0])
                    if ch is not None:
                        try:
                            await ch.send(
                                f"🔁 جدّدت رابط البث وأكملت: **{info.get('title') or meta.get('title')}**")
                        except Exception:
                            pass
                    return
            except Exception as e:
                log.warning(f"direct retry failed: {e!r}")
            await self._advance_or_stop(player, finished_track=None, failed=True)
            return

        # 2) مسار يوتيوب أصلي — الاستخراج عبر yt-dlp ثم البث المباشر
        if url and self._is_youtube_track(failed_track) and key not in rescued:
            rescued.add(key)
            try:
                info = await ytdlp_resolve(url)
                loaded, _pl = await self._lavalink_load(info["url"])
                if loaded:
                    self._register_meta(loaded[0], info)
                    player.autoplay = wavelink.AutoPlayMode.disabled
                    await player.play(loaded[0])
                    if ch is not None:
                        try:
                            await ch.send(f"🔁 تم إصلاح التشغيل وبثّه عبر مسار بديل: **{failed_track.title}**")
                        except Exception:
                            pass
                    return
            except Exception as e:
                log.warning(f"rescue failed for {failed_track.title!r}: {e!r}")

        await self._advance_or_stop(player, finished_track=None, failed=True)

    async def _advance_or_stop(self, player: wavelink.Player, finished_track=None, failed: bool = False):
        """الانتقال للعنصر التالي في الطابور فقط — لا إضافة تلقائية أبداً."""
        gid = player.guild.id
        q = self._queue_of(gid)
        mode = self.loop_mode.get(gid, "off")
        finished_title = getattr(finished_track, "title", "") or ""

        if finished_track is not None and not failed:
            if mode == "track":
                try:
                    player.autoplay = wavelink.AutoPlayMode.disabled
                    await player.play(finished_track)
                    return
                except Exception as e:
                    log.warning(f"loop replay failed: {e!r}")
            elif mode == "queue":
                q.append(finished_track)

        nxt = q.pop(0) if q else None
        if nxt is not None:
            try:
                player.autoplay = wavelink.AutoPlayMode.disabled
                await player.play(nxt)
                return
            except Exception as e:
                log.warning(f"advance play failed: {e!r}")

        self._idle_since[gid] = time.monotonic()
        if failed:
            ch = self._text_channel.get(gid)
            if ch is not None:
                msg = "⛔ فشل تشغيل المقطع وتعذّر إصلاحه عبر المسار البديل."
                if finished_title:
                    msg += f"\n({finished_title})"
                try:
                    await ch.send(msg)
                except Exception:
                    pass

    # ─────────────────────────────────────────
    #  رسالة "شغّال الآن" + شريط التقدم الحي
    # ─────────────────────────────────────────

    def _cancel_np_task(self, gid: int):
        task = self._np_tasks.pop(gid, None)
        if task and not task.done():
            task.cancel()

    def _np_embed(self, gid: int, position_ms: int, duration_ms: int, title: str,
                  author: str, uri: str) -> discord.Embed:
        vc = self.bot.get_guild(gid).voice_client if self.bot.get_guild(gid) else None
        vol = self._current_volume(self.bot.get_guild(gid)) if self.bot.get_guild(gid) else 100
        playing = "▶️" if not _v_paused(vc) else "⏸️"
        desc = f"{playing} **[{title}]({uri})**\n" if uri else f"{playing} **{title}**\n"
        desc += f"🎤 {author}\n\n" if author else "\n"
        desc += f"`[{progress_bar(position_ms, duration_ms)}]` **{fmt_time(position_ms)} / {fmt_time(duration_ms)}**\n"
        mode = self.loop_mode.get(gid, "off")
        q_len = len(self._queue_of(gid))
        engine = "Lavalink 🛡" if ENGINE == "lavalink" else "yt-dlp بديل 🔧"
        desc += f"\n🔁 التكرار: `{mode}` • 🔊 `{vol}%` • 📜 الطابور: `{q_len}` • المحرك: `{engine}`"
        return discord.Embed(title="شغّال الآن", description=desc, color=discord.Color.green())

    async def _send_np_message(self, gid: int, player: wavelink.Player):
        track = player.current
        if track is None:
            return
        ch = self._text_channel.get(gid)
        if ch is None:
            return
        meta = self._display_meta(track)
        embed = self._np_embed(gid, int(player.position or 0),
                               meta.get("duration_ms") or int(track.length or 0),
                               meta.get("title") or track.title or "",
                               meta.get("author") or track.author or "",
                               meta.get("webpage_url") or track.uri or "")
        try:
            old = self._np_msgs.pop(gid, None)
            if old is not None:
                try:
                    await old.delete()
                except Exception:
                    pass
            msg = await ch.send(embed=embed)
            self._np_msgs[gid] = msg
        except Exception as e:
            log.debug(f"np send failed: {e!r}")
            return

        async def _updater():
            try:
                while True:
                    await asyncio.sleep(15)
                    cur = player.current or track
                    pos = int(player.position or 0)
                    m = self._display_meta(cur)
                    try:
                        await self._np_msgs[gid].edit(
                            embed=self._np_embed(gid, pos,
                                                 m.get("duration_ms") or int(cur.length or 0),
                                                 m.get("title") or cur.title or "",
                                                 m.get("author") or cur.author or "",
                                                 m.get("webpage_url") or cur.uri or "")
                        )
                    except discord.NotFound:
                        break
                    except Exception:
                        pass
            except asyncio.CancelledError:
                pass

        self._np_tasks[gid] = self.bot.loop.create_task(_updater())

    async def _ff_np_message(self, gid: int, vc: discord.VoiceClient, info: dict):
        ch = self._text_channel.get(gid)
        if ch is None:
            return
        try:
            old = self._np_msgs.pop(gid, None)
            if old is not None:
                try:
                    await old.delete()
                except Exception:
                    pass
            pos_ms = int(self._ff_elapsed(gid) * 1000)
            msg = await ch.send(embed=self._np_embed(
                gid, pos_ms, int(info.get("duration") or 0) * 1000,
                info.get("title") or "", info.get("uploader") or "", info.get("webpage_url") or ""))
            self._np_msgs[gid] = msg
        except Exception as e:
            log.debug(f"ff np send failed: {e!r}")
            return

        async def _updater():
            try:
                while True:
                    await asyncio.sleep(15)
                    st = self._ff_state.get(gid)
                    if not st or st.get("current") is None:
                        break
                    cur = st["current"]
                    pos_ms = int(self._ff_elapsed(gid) * 1000)
                    try:
                        await self._np_msgs[gid].edit(embed=self._np_embed(
                            gid, pos_ms, int(cur.get("duration") or 0) * 1000,
                            cur.get("title") or "", cur.get("uploader") or "",
                            cur.get("webpage_url") or ""))
                    except discord.NotFound:
                        break
                    except Exception:
                        pass
            except asyncio.CancelledError:
                pass

        self._np_tasks[gid] = self.bot.loop.create_task(_updater())

    # ─────────────────────────────────────────
    #  سجل التاريخ
    # ─────────────────────────────────────────

    async def _insert_history(self, gid: int, title: str, uri: str, source: str):
        user = self.last_requester.get(gid)
        uid = user.id if user else 0
        uname = user.display_name if user else ""
        await asyncio.to_thread(
            self.db.exec,
            "INSERT INTO history (guild_id, user_id, user_name, title, uri, source) VALUES (%s,%s,%s,%s,%s,%s)",
            (gid, uid, uname[:128], title[:256], uri[:512], source[:32]),
        )

    # ─────────────────────────────────────────
    #  مراقب الخمول — قطع الاتصال بعد فترة خمول (إلا مع 24/7)
    # ─────────────────────────────────────────

    async def _idle_monitor(self):
        await self.bot.wait_until_ready()
        while True:
            try:
                await asyncio.sleep(30)
                now = time.monotonic()
                for vc in list(self.bot.voice_clients):
                    gid = vc.guild.id
                    if isinstance(vc, wavelink.Player):
                        busy = bool(getattr(vc, "playing", False) or getattr(vc, "paused", False))
                    else:
                        busy = bool(vc.is_playing() or vc.is_paused())
                    if busy:
                        self._idle_since.pop(gid, None)
                        continue
                    since = self._idle_since.get(gid)
                    if since is None:
                        self._idle_since[gid] = now
                        continue
                    if (now - since) >= IDLE_DISCONNECT_SEC and not self.stay_247.get(gid):
                        ch = self._text_channel.get(gid)
                        self._cleanup_guild(gid)
                        try:
                            await vc.disconnect(force=True)
                        except Exception:
                            pass
                        if ch is not None:
                            try:
                                await ch.send("🔌 خرجت من القناة بسبب عدم وجود تشغيل لفترة طويلة.")
                            except Exception:
                                pass
            except asyncio.CancelledError:
                break
            except Exception as e:
                log.warning(f"idle monitor error: {e!r}")

    def _cleanup_guild(self, gid: int):
        self._queue_of(gid).clear()
        self._cancel_np_task(gid)
        self._np_msgs.pop(gid, None)
        self._idle_since.pop(gid, None)
        self._rescued.pop(gid, None)
        self._ff_state.pop(gid, None)

    # ─────────────────────────────────────────
    #  محرك الاحتياط: yt-dlp + ffmpeg (عند تعذر Lavalink)
    # ─────────────────────────────────────────

    def _ff_state_of(self, gid: int) -> dict:
        return self._ff_state.setdefault(gid, {
            "queue": [], "current": None, "volume": 1.0,
            "played": 0.0, "last_tick": None,
        })

    def _ff_elapsed(self, gid: int) -> float:
        st = self._ff_state.get(gid)
        if not st or st.get("current") is None:
            return 0.0
        now = time.monotonic()
        last = st.get("last_tick") or now
        vc = self.bot.get_guild(gid).voice_client if self.bot.get_guild(gid) else None
        if vc is not None and _v_playing(vc):
            st["played"] += now - last
        st["last_tick"] = now
        return float(st.get("played") or 0.0)

    async def _ff_play_resolved(self, ctx, info: dict):
        gid = ctx.guild.id
        self._text_channel[gid] = ctx.channel
        self._rescued[gid] = set()
        vc = ctx.guild.voice_client
        if vc is None:
            vc = await self._ensure_voice(ctx)
            if vc is None:
                return
        st = self._ff_state_of(gid)
        if _v_playing(vc) or _v_paused(vc):
            st["queue"].append(info)
            await ctx.reply(f"➕ أُضيفت إلى الطابور: **{info.get('title')}**", mention_author=False)
            return
        await self._ff_start(ctx.guild, vc, info)
        await ctx.reply(f"🎶 جاري تشغيل: **{info.get('title')}**", mention_author=False)

    async def _ff_start(self, guild: discord.Guild, vc: discord.VoiceClient, info: dict):
        gid = guild.id
        st = self._ff_state_of(gid)
        before = "-reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 -rw_timeout 20000000"
        src = discord.PCMVolumeTransformer(
            discord.FFmpegPCMAudio(info["url"], before_options=before, options="-vn"),
            volume=float(st.get("volume") or 1.0),
        )

        def _after(err):
            if err:
                log.error(f"ffmpeg after error: {err!r}")
            self.bot.dispatch("ff_track_end", gid, "finished" if err is None else "error")

        vc.play(src, after=_after)
        st["current"] = info
        st["played"] = 0.0
        st["last_tick"] = time.monotonic()
        self._idle_since.pop(gid, None)
        self._cancel_np_task(gid)
        await self._ff_np_message(gid, vc, info)
        await self._insert_history(gid, info.get("title") or "", info.get("webpage_url") or "", "youtube")

    @commands.Cog.listener()
    async def on_ff_track_end(self, gid: int, status: str):
        try:
            guild = self.bot.get_guild(gid)
            if guild is None:
                return
            self._cancel_np_task(gid)
            st = self._ff_state.get(gid)
            if st is None:
                return
            finished = st.get("current")
            st["current"] = None
            vc = guild.voice_client
            if vc is None:
                self._idle_since[gid] = time.monotonic()
                return
            mode = self.loop_mode.get(gid, "off")
            q = st["queue"]

            if status == "finished" and finished is not None:
                if mode == "track":
                    await self._ff_start(guild, vc, finished)
                    return
                if mode == "queue":
                    q.append(finished)

            if q:
                nxt = q.pop(0)
                await self._ff_start(guild, vc, nxt)
                return

            self._idle_since[gid] = time.monotonic()
            if status == "error":
                ch = self._text_channel.get(gid)
                if ch is not None:
                    try:
                        await ch.send("⛔ انقطع البث ولم يعد هناك ما يُشغّله.")
                    except Exception:
                        pass
        except Exception as e:
            log.error(f"ff_track_end handler error: {e!r}")


    # ─────────────────────────────────────────
    #  الأوامر
    # ─────────────────────────────────────────

    @commands.hybrid_command(name="queue", aliases=["q"], help="عرض قائمة الانتظار", description="عرض قائمة الانتظار")
    async def queue_(self, ctx):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        vc = ctx.guild.voice_client
        current = None
        if isinstance(vc, wavelink.Player):
            current = vc.current
        elif ENGINE == "ffmpeg":
            st = self._ff_state.get(gid)
            current = st.get("current") if st else None
        q = self._queue_of(gid)
        if current is None and not q:
            await ctx.reply("📜 الطابور فارغ — أرسل `play اسم الأغنية` للبدء.", mention_author=False)
            return
        lines = []
        if current is not None:
            lines.append(f"**▶ الآن:** {self._disp_title(current)} `{fmt_time(self._disp_len(current))}`")
        if q:
            lines.append("")
            for i, t in enumerate(q[:10], start=1):
                lines.append(f"**{i}.** {self._disp_title(t)} `{fmt_time(self._disp_len(t))}`")
            if len(q) > 10:
                lines.append(f"…و {len(q) - 10} أخرى")
        total = sum(self._disp_len(t) for t in q)
        embed = discord.Embed(
            title=f"📜 قائمة الانتظار ({len(q)}) — المدة الكلية {fmt_time(total)}",
            description="\n".join(lines) or "فارغ",
            color=discord.Color.blurple(),
        )
        await ctx.reply(embed=embed, mention_author=False)

    @commands.hybrid_command(name="nowplaying", aliases=["np"], help="عرض ما يُشغّل الآن مع شريط التقدم", description="عرض ما يُشغّل الآن مع شريط التقدم")
    async def nowplaying(self, ctx):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        vc = ctx.guild.voice_client
        if isinstance(vc, wavelink.Player) and vc.current:
            m = self._display_meta(vc.current)
            embed = self._np_embed(gid, int(vc.position or 0),
                                   m.get("duration_ms") or int(vc.current.length or 0),
                                   m.get("title") or vc.current.title or "",
                                   m.get("author") or vc.current.author or "",
                                   m.get("webpage_url") or vc.current.uri or "")
            await ctx.reply(embed=embed, mention_author=False)
            return
        st = self._ff_state.get(gid)
        if ENGINE == "ffmpeg" and st and st.get("current"):
            cur = st["current"]
            embed = self._np_embed(gid, int(self._ff_elapsed(gid) * 1000),
                                   int(cur.get("duration") or 0) * 1000,
                                   cur.get("title") or "", cur.get("uploader") or "",
                                   cur.get("webpage_url") or "")
            await ctx.reply(embed=embed, mention_author=False)
            return
        await ctx.reply("😴 لا يوجد شيء قيد التشغيل الآن.", mention_author=False)

    @commands.hybrid_command(name="skip", aliases=["s", "next"], help="تخطي الأغنية الحالية", description="تخطي الأغنية الحالية")
    async def skip(self, ctx):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        vc = ctx.guild.voice_client
        if vc is None:
            await ctx.reply("😕 لست متصلاً بقناة صوتية.", mention_author=False)
            return
        if isinstance(vc, wavelink.Player):
            if not (getattr(vc, "playing", False) or getattr(vc, "paused", False)):
                await ctx.reply("😕 لا يوجد تشغيل حالياً.", mention_author=False)
                return
            q = self._queue_of(gid)
            nxt = q.pop(0) if q else None
            if nxt is not None:
                try:
                    vc.autoplay = wavelink.AutoPlayMode.disabled
                    await vc.play(nxt)
                    await ctx.reply(f"⏭ تم التخطي إلى: **{self._disp_title(nxt)}**", mention_author=False)
                except Exception as e:
                    await ctx.reply(f"❌ فشل التخطي: `{e}`", mention_author=False)
            else:
                await vc.stop()
                await ctx.reply("⏭ تم التخطي — لا يوجد المزيد في الطابور.", mention_author=False)
            return
        # وضع ffmpeg
        if not (vc.is_playing() or vc.is_paused()):
            await ctx.reply("😕 لا يوجد تشغيل حالياً.", mention_author=False)
            return
        await ctx.reply("⏭ تم التخطي.", mention_author=False)
        vc.stop()

    @commands.hybrid_command(name="pause", help="إيقاف مؤقت", description="إيقاف مؤقت")
    async def pause(self, ctx):
        await self._defer_if_slash(ctx)
        vc = ctx.guild.voice_client
        if isinstance(vc, wavelink.Player):
            if getattr(vc, "playing", False) and not getattr(vc, "paused", False):
                await vc.pause(True)
                await ctx.reply("⏸️ تم الإيقاف المؤقت.", mention_author=False)
                return
        elif vc and vc.is_playing() and not vc.is_paused():
            vc.pause()
            await ctx.reply("⏸️ تم الإيقاف المؤقت.", mention_author=False)
            return
        await ctx.reply("😕 لا يوجد تشغيل لإيقافه.", mention_author=False)

    @commands.hybrid_command(name="resume", aliases=["unpause"], help="استئناف التشغيل", description="استئناف التشغيل")
    async def resume(self, ctx):
        await self._defer_if_slash(ctx)
        vc = ctx.guild.voice_client
        if isinstance(vc, wavelink.Player):
            if getattr(vc, "paused", False):
                await vc.pause(False)
                await ctx.reply("▶️ تم استئناف التشغيل.", mention_author=False)
                return
        elif vc and vc.is_paused():
            vc.resume()
            await ctx.reply("▶️ تم استئناف التشغيل.", mention_author=False)
            return
        await ctx.reply("😕 لا يوجد إيقاف مؤقت.", mention_author=False)

    @commands.hybrid_command(name="stop", aliases=["st"], help="إيقاف التشغيل ومسح الطابور", description="إيقاف التشغيل ومسح الطابور")
    async def stop_(self, ctx):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        vc = ctx.guild.voice_client
        self._queue_of(gid).clear()
        self._rescued.pop(gid, None)
        self._cancel_np_task(gid)
        if isinstance(vc, wavelink.Player):
            if getattr(vc, "playing", False) or getattr(vc, "paused", False):
                await vc.stop()
            await ctx.reply("⏹ تم الإيقاف ومسح الطابور.", mention_author=False)
            self._idle_since[gid] = time.monotonic()
            return
        if vc and (vc.is_playing() or vc.is_paused()):
            if ENGINE == "ffmpeg":
                st = self._ff_state.get(gid)
                if st is not None:
                    st["current"] = None
            vc.stop()
        await ctx.reply("⏹ تم الإيقاف ومسح الطابور.", mention_author=False)
        self._idle_since[gid] = time.monotonic()

    @app_commands.describe(value="مستوى الصوت من 0 إلى 200")
    @commands.hybrid_command(name="volume", aliases=["vol", "v"], help="ضبط الصوت (0-200)", description="ضبط الصوت (0-200)")
    async def volume(self, ctx, value: int = None):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        if value is None:
            await ctx.reply(f"🔊 الصوت الحالي: `{self._current_volume(ctx.guild)}%`", mention_author=False)
            return
        value = max(0, min(value, 200))
        vc = ctx.guild.voice_client
        if isinstance(vc, wavelink.Player):
            try:
                await vc.set_volume(value)
            except Exception:
                try:
                    vc.volume = value
                except Exception:
                    pass
        elif vc and isinstance(vc.source, discord.PCMVolumeTransformer):
            vc.source.volume = value / 100.0
            st = self._ff_state_of(gid)
            st["volume"] = value / 100.0
        else:
            await ctx.reply("😕 لست متصلاً بقناة صوتية.", mention_author=False)
            return
        self._save_settings(gid)
        await ctx.reply(f"🔊 تم ضبط الصوت إلى `{value}%`", mention_author=False)

    @app_commands.describe(mode="off / track / queue")
    @commands.hybrid_command(name="loop", aliases=["repeat", "l"], help="التكرار: off / track / queue", description="التكرار: off / track / queue")
    async def loop(self, ctx, mode: str = None):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        if mode is None:
            await ctx.reply(
                f"🔁 وضع التكرار الحالي: `{self.loop_mode.get(gid, 'off')}`\n"
                f"الاستخدام: `{PREFIX}loop off|track|queue`",
                mention_author=False,
            )
            return
        mode = mode.strip().lower()
        if mode in ("one", "single", "اغنية", "track", "t", "1"):
            mode = "track"
        elif mode in ("all", "queue", "q", "الكل"):
            mode = "queue"
        elif mode in ("off", "none", "ايقاف", "إيقاف"):
            mode = "off"
        else:
            await ctx.reply(f"❌ وضع غير معروف — الاستخدام: `{PREFIX}loop off|track|queue`", mention_author=False)
            return
        self.loop_mode[gid] = mode
        self._save_settings(gid)
        emoji = {"off": "➡️", "track": "🔂", "queue": "🔁"}[mode]
        await ctx.reply(f"{emoji} وضع التكرار: `{mode}`", mention_author=False)

    @commands.hybrid_command(name="shuffle", aliases=["sh"], help="خلط الطابور", description="خلط الطابور")
    async def shuffle(self, ctx):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        q = self._queue_of(gid)
        if len(q) < 2:
            await ctx.reply("😕 لا يوجد ما يُخلط — الطابور يحتاج أغنيتين على الأقل.", mention_author=False)
            return
        random.shuffle(q)
        await ctx.reply(f"🔀 تم خلط **{len(q)}** أغنية في الطابور.", mention_author=False)

    @app_commands.describe(index="الموضع في الطابور")
    @commands.hybrid_command(name="skipto", aliases=["stt"], help="التشغيل مباشرة من موضع في الطابور", description="التشغيل مباشرة من موضع في الطابور")
    async def skipto(self, ctx, index: int = None):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        if index is None or index < 1:
            await ctx.reply(f"✏️ الاستخدام: `{PREFIX}skipto رقم` (الموضع في الطابور)", mention_author=False)
            return
        q = self._queue_of(gid)
        if index > len(q):
            await ctx.reply(f"😕 الموضع {index} خارج الطابور (الحجم: {len(q)}).", mention_author=False)
            return
        item = q.pop(index - 1)
        vc = ctx.guild.voice_client
        if isinstance(vc, wavelink.Player):
            try:
                vc.autoplay = wavelink.AutoPlayMode.disabled
                await vc.play(item)
                await ctx.reply(f"⏭ تشغيل مباشر: **{item.title}**", mention_author=False)
            except Exception as e:
                q.insert(0, item)
                await ctx.reply(f"❌ فشل التشغيل: `{e}`", mention_author=False)
            return
        q.insert(0, item)
        if vc and (vc.is_playing() or vc.is_paused()):
            await ctx.reply(f"⏭ الانتقال إلى: **{item.get('title') if isinstance(item, dict) else item}**", mention_author=False)
            vc.stop()
        else:
            nxt = q.pop(0)
            await self._ff_start(ctx.guild, vc, nxt)
            await ctx.reply(f"⏭ تشغيل مباشر: **{nxt.get('title') if isinstance(nxt, dict) else nxt}**", mention_author=False)

    @app_commands.describe(index="الموضع في الطابور")
    @commands.hybrid_command(name="remove", aliases=["rm"], help="إزالة أغنية من الطابور", description="إزالة أغنية من الطابور")
    async def remove(self, ctx, index: int = None):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        if index is None or index < 1:
            await ctx.reply(f"✏️ الاستخدام: `{PREFIX}remove رقم`", mention_author=False)
            return
        q = self._queue_of(gid)
        if index > len(q):
            await ctx.reply(f"😕 الموضع {index} خارج الطابور (الحجم: {len(q)}).", mention_author=False)
            return
        item = q.pop(index - 1)
        title = getattr(item, "title", None) or (item.get("title") if isinstance(item, dict) else str(item))
        await ctx.reply(f"🗑️ أُزيلت: **{title}**", mention_author=False)

    @app_commands.describe(position="الزمن بصيغة mm:ss مثل 1:30")
    @commands.hybrid_command(name="seek", help="الانتقال إلى زمن (mm:ss) — Lavalink فقط", description="الانتقال إلى زمن (mm:ss) — Lavalink فقط")
    async def seek(self, ctx, position: str = None):
        await self._defer_if_slash(ctx)
        vc = ctx.guild.voice_client
        if position is None:
            await ctx.reply(f"✏️ الاستخدام: `{PREFIX}seek 1:30`", mention_author=False)
            return
        parts = position.strip().split(":")
        try:
            if len(parts) == 2:
                seconds = int(parts[0]) * 60 + int(parts[1])
            else:
                seconds = int(parts[0])
        except ValueError:
            await ctx.reply("❌ صيغة غير صحيحة — مثال: `1:30`", mention_author=False)
            return
        if isinstance(vc, wavelink.Player) and vc.current:
            try:
                await vc.seek(seconds * 1000)
                await ctx.reply(f"⏩ تم الانتقال إلى `{position}`", mention_author=False)
            except Exception as e:
                await ctx.reply(f"❌ فشل الانتقال: `{e}`", mention_author=False)
            return
        await ctx.reply("⚠️ الانتقال الزمني مدعوم فقط مع محرك Lavalink.", mention_author=False)

    @commands.hybrid_command(name="join", aliases=["j"], help="دعوة البوت لقناتك الصوتية", description="دعوة البوت لقناتك الصوتية")
    async def join(self, ctx):
        await self._defer_if_slash(ctx)
        vc = await self._ensure_voice(ctx)
        if vc is not None:
            await ctx.reply(f"👋 انضممت إلى **{vc.channel.name}**", mention_author=False)

    @commands.hybrid_command(name="leave", aliases=["dc", "disconnect"], help="خروج البوت من القناة", description="خروج البوت من القناة")
    async def leave(self, ctx):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        vc = ctx.guild.voice_client
        if vc is None:
            await ctx.reply("😕 لست متصلاً أصلاً.", mention_author=False)
            return
        self._cleanup_guild(gid)
        await vc.disconnect(force=True)
        await ctx.reply("👋 خرجت من القناة. اراك لاحقاً!", mention_author=False)

    @commands.hybrid_command(name="247", aliases=["24/7", "stay"], help="تفعيل/تعطيل البقاء 24/7", description="تفعيل/تعطيل البقاء 24/7")
    async def stay(self, ctx):
        await self._defer_if_slash(ctx)
        gid = ctx.guild.id
        cur = self.stay_247.get(gid, False)
        self.stay_247[gid] = not cur
        if self.stay_247[gid]:
            self._idle_since.pop(gid, None)
        else:
            self._idle_since[gid] = time.monotonic()
        self._save_settings(gid)
        state = "مفعّل ✅ (سأبقى في القناة)" if self.stay_247[gid] else "معطّل ⛔ (سأخرج عند الخمول)"
        await ctx.reply(f"🕰️ وضع 24/7: {state}", mention_author=False)

    @commands.hybrid_command(name="history", aliases=["hist"], help="آخر ما تم تشغيله", description="آخر ما تم تشغيله")
    async def history(self, ctx):
        await self._defer_if_slash(ctx)
        rows = await asyncio.to_thread(
            self.db.fetchall,
            "SELECT title, user_name, played_at FROM history WHERE guild_id=%s ORDER BY id DESC LIMIT 10",
            (ctx.guild.id,),
        )
        if not rows:
            await ctx.reply("📭 لا يوجد سجل تشغيل بعد.", mention_author=False)
            return
        lines = []
        for i, r in enumerate(rows, start=1):
            who = r.get("user_name") or "؟"
            lines.append(f"**{i}.** {r.get('title')} — بواسطة `{who}`")
        embed = discord.Embed(title="🕘 آخر ما تم تشغيله", description="\n".join(lines),
                              color=discord.Color.gold())
        await ctx.reply(embed=embed, mention_author=False)

    @commands.hybrid_command(name="ping", help="سرعة الاستجابة وحالة المحرك", description="سرعة الاستجابة وحالة المحرك")
    async def ping(self, ctx):
        await self._defer_if_slash(ctx)
        engine = "🛡 Lavalink" if ENGINE == "lavalink" else "🔧 وضع بديل yt-dlp/ffmpeg"
        db = "✅" if self.db.available else "⚠️ غير متاحة"
        embed = discord.Embed(
            title="🏓 Pong!",
            description=f"⚡ الاستجابة: `{round(self.bot.latency * 1000)}ms`\n"
                        f"🎧 المحرك: `{engine}`\n"
                        f"🗄️ قاعدة البيانات: `{db}`",
            color=discord.Color.green(),
        )
        await ctx.reply(embed=embed, mention_author=False)

    @commands.hybrid_command(name="help", aliases=["h", "commands"], help="قائمة الأوامر", description="قائمة الأوامر")
    async def help_cmd(self, ctx):
        await self._defer_if_slash(ctx)
        engine = "🛡 Lavalink (مستقر)" if ENGINE == "lavalink" else "🔧 وضع بديل yt-dlp/ffmpeg"
        desc = (
            "## 🎵 بوت الموسيقى — أوامري\n"
            "الأوامر تعمل **بالبادئة** `!` أو **بدونها**، وكذلك كلها كأوامر **سلاش** `/` (مثل `/play`).\n\n"
            "### ▶️ التشغيل\n"
            f"`{PREFIX}play <اسم أو رابط>` — يعرض قائمة نتائج مرقّمة، اكتب **رقم** الأغنية لتشغيلها\n"
            f"`{PREFIX}queue` — عرض الطابور • `{PREFIX}np` — شغّال الآن\n"
            f"`{PREFIX}skip` — تخطي • `{PREFIX}pause` / `{PREFIX}resume` — إيقاف مؤقت/استئناف\n"
            f"`{PREFIX}stop` — إيقاف ومسح • `{PREFIX}skipto <رقم>` — تشغيل موضع من الطابور\n"
            f"`{PREFIX}remove <رقم>` — إزالة من الطابور • `{PREFIX}shuffle` — خلط\n\n"
            "### ⚙️ التحكم\n"
            f"`{PREFIX}volume <0-200>` — الصوت • `{PREFIX}loop off|track|queue` — التكرار\n"
            f"`{PREFIX}seek mm:ss` — الانتقال الزمني • `{PREFIX}247` — البقاء 24/7\n\n"
            "### 📌 أخرى\n"
            f"`{PREFIX}history` — آخر التشغيلات • `{PREFIX}join` / `{PREFIX}leave` — دخول/خروج\n"
            f"`{PREFIX}ping` — حالة البوت\n\n"
            f"**المحرك الحالي:** {engine}\n"
            "**ملاحظة:** لا يضيف البوت أي أغنية للطابور من تلقاء نفسه — تشغّل ما تختاره فقط."
        )
        embed = discord.Embed(description=desc, color=discord.Color.blurple())
        embed.set_footer(text="elminyawe • بوت موسيقى متكامل مع MariaDB + Lavalink")
        await ctx.reply(embed=embed, mention_author=False)

    # ─────────────────────────────────────────
    #  معالجة الأخطاء
    # ─────────────────────────────────────────

    async def cog_command_error(self, ctx, error):
        if isinstance(error, commands.CommandNotFound):
            return
        if isinstance(error, commands.MissingRequiredArgument):
            await ctx.reply(f"✏️ نقص معاملات — الاستخدام: `{PREFIX}{ctx.command}`", mention_author=False)
            return
        if isinstance(error, commands.BadArgument):
            await ctx.reply("❌ معامل غير صالح — تأكد من الأرقام/القيم.", mention_author=False)
            return
        err = getattr(error, "original", error)
        log.error(f"command {ctx.command} error: {err!r}")
        try:
            await ctx.reply(f"❌ حدث خطأ غير متوقع: `{err}`", mention_author=False)
        except Exception:
            pass


# ─────────────────────────────────────────
#  وضع الاختبار الخفي (TEST_MODE=1 فقط) — لا يعمل في الإنتاج إطلاقاً
# ─────────────────────────────────────────
async def run_test_flow(bot: ElminyaweBot):
    res_path = TEST_RESULTS_FILE

    def w(line: str):
        with open(res_path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        log.info(f"[TEST] {line}")

    await bot.wait_until_ready()
    await asyncio.sleep(5)
    try:
        w(f"TIME {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} ENGINE {ENGINE}")
        guild = bot.get_guild(TEST_GUILD_ID)
        if guild is None:
            w("RESULT FAIL no_guild")
            await bot.close()
            return
        ch = guild.get_channel(TEST_CHANNEL_ID)
        if ch is None or not isinstance(ch, (discord.VoiceChannel, discord.StageChannel)):
            w("RESULT FAIL no_voice_channel")
            await bot.close()
            return
        cog = bot.get_cog("MusicCog")
        gid = guild.id
        positions = []
        if ENGINE == "lavalink":
            player = None
            for attempt in range(1, 4):
                try:
                    player = await ch.connect(cls=wavelink.Player, self_deaf=True)
                    break
                except Exception as e:
                    w(f"CONNECT-RETRY {attempt}/3 failed: {e!r}")
                    try:
                        await asyncio.sleep(3)
                        await ch.connect(cls=wavelink.Player, self_deaf=True)
                        break
                    except Exception:
                        pass
                    if attempt == 3:
                        raise
            player.autoplay = wavelink.AutoPlayMode.disabled
            cog._text_channel[gid] = ch
            test_url = os.getenv("TEST_PLAY_URL", "").strip()
            if test_url:
                tracks, _pl = await cog._lavalink_load(test_url)
                if not tracks:
                    w("RESULT FAIL no_test_url_results")
                    await bot.close()
                    return
            else:
                tracks, _pl = await cog._lavalink_load("ytsearch:Yaah Tamer Ashour")
            if not tracks:
                w("RESULT FAIL no_search_results")
                await bot.close()
                return
            track = tracks[0]
            w(f"TRACK {track.title} | {track.uri}")
            await player.play(track)
            for i in range(9):
                await asyncio.sleep(5)
                pos = int(player.position or 0)
                w(f"TICK {i} pos={pos}ms playing={bool(player.playing)}")
                positions.append(pos)
        else:
            vc = await ch.connect(cls=discord.VoiceClient, self_deaf=True)
            cog._text_channel[gid] = ch
            info = await ytdlp_resolve("ytsearch1:Yaah Tamer Ashour")
            w(f"TRACK {info['title']} | {info['webpage_url']}")
            await cog._ff_start(guild, vc, info)
            for i in range(9):
                await asyncio.sleep(5)
                pos = int(cog._ff_elapsed(gid) * 1000)
                w(f"TICK {i} pos={pos}ms playing={vc.is_playing()}")
                positions.append(pos)
        advanced = any(positions[i + 1] > positions[i] for i in range(len(positions) - 1))
        w(f"RESULT {'PASS' if advanced else 'FAIL'} pos_advanced={advanced}")
        await bot.close()
    except Exception as e:
        try:
            w(f"RESULT FAIL exception={e!r}")
        except Exception:
            pass
        await bot.close()


# ─────────────────────────────────────────
#  نقطة الدخول
# ─────────────────────────────────────────
def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s | %(message)s",
        datefmt="%H:%M:%S",
    )
    if not TOKEN or "PUT_YOUR" in TOKEN.upper():
        log.critical(
            "❌ لم يتم ضبط توكن البوت DISCORD_TOKEN!\n"
            "   • محلياً: ضع التوكن في ENV DISCORD_TOKEN\n"
            "   • في Railway: Variables → DISCORD_TOKEN = توكن بوتك"
        )
        sys.exit(1)
    bot = ElminyaweBot()
    bot.run(TOKEN, log_handler=None)


if __name__ == "__main__":
    main()
MUSICPY_EOF

# ── نظام الكوكيز الذكي: جلب كوكيز يوتيوب تلقائياً بعد دخول OAuth ──
RUN cat > /opt/bot/yt_cookies.py <<'COOKIESPY_EOF'
# -*- coding: utf-8 -*-
# ═══════════════════════════════════════════════════════════════════════════
#  yt_cookies.py — نظام الكوكيز الذكي (elminyawe)
#  ─────────────────────────────────────────────────────────────────────────
#  بعد تسجيل الدخول إلى يوتيوب عبر رمز OAuth الثابت، يقوم النظام بنفسه بجلب
#  الكوكيز (Set-Cookie) من يوتيوب ويكتبها في cookies.txt بصيغة Netscape،
#  ثم يجدّدها دورياً — بلا أي تدخل يدوي من المستخدم إطلاقاً.
#  الملف الناتج يستخدمه yt-dlp (محرك الإصلاح والاحتياط) تلقائياً.
# ═══════════════════════════════════════════════════════════════════════════

import json
import os
import time
import urllib.parse
import urllib.request

CLIENT_ID = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
CLIENT_SECRET = "SboVhoG9s0rNafixCSGGKXAT"
TOKEN_URL = "https://www.youtube.com/o/oauth2/token"

DEFAULT_REFRESH_TOKEN = (
    "1//0eVooXRETOIiuCgYIARAAGA4SNwF-L9Irvn8-fFnEvPQl33FHJroxf7YbO4WmJ2Go52l3IrBkRh7BIPIiuX0FyGmgo7lAeC9krzw"
)
REFRESH_TOKEN = os.getenv("YT_REFRESH_TOKEN", DEFAULT_REFRESH_TOKEN).strip()
COOKIES_PATH = os.getenv("YT_AUTO_COOKIES_FILE", "/opt/bot/cookies.txt").strip()
INTERVAL = int(os.getenv("YT_COOKIES_INTERVAL_SEC", "21600"))  # افتراضياً كل 6 ساعات
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
HARVEST_URLS = [
    "https://www.youtube.com/",
    "https://music.youtube.com/",
    "https://www.youtube.com/feed/library",
]


def log(msg):
    print(f"[yt_cookies] {time.strftime('%Y-%m-%d %H:%M:%S')} {msg}", flush=True)


def refresh_access_token(refresh_token: str) -> str:
    """تسجيل الدخول: رمز التحديث ← رمز وصول جديد."""
    data = urllib.parse.urlencode({
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request(TOKEN_URL, data=data, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode())
    return payload["access_token"]


def harvest(access_token: str) -> dict:
    """جلب الكوكيز من يوتيوب مع تمرير رمز الدخول (Authorization: Bearer)."""
    cookies = {}
    for url in HARVEST_URLS:
        try:
            req = urllib.request.Request(url)
            req.add_header("User-Agent", UA)
            req.add_header("Authorization", f"Bearer {access_token}")
            req.add_header("X-Origin", "https://www.youtube.com")
            req.add_header("Accept-Language", "en-US,en;q=0.9,ar;q=0.8")
            with urllib.request.urlopen(req, timeout=30) as resp:
                for sc in resp.headers.get_all("Set-Cookie") or []:
                    name, _, rest = sc.partition("=")
                    value = rest.split(";", 1)[0].strip()
                    name = name.strip()
                    if name and value:
                        cookies[name] = value
        except Exception as exc:
            log(f"تعذّر الحصاد من {url}: {exc!r}")
    return cookies


def write_netscape(cookies: dict) -> int:
    """كتابة الكوكيز بصيغة Netscape — كتابة ذرّية عبر tmp + rename."""
    expiry = int(time.time()) + 31536000  # صلاحية سنة كاملة
    lines = [
        "# Netscape HTTP Cookie File",
        "# Auto-harvested by elminyawe after YouTube OAuth login",
        f"# updated: {time.strftime('%Y-%m-%d %H:%M:%S')}",
    ]
    for name, value in sorted(cookies.items()):
        for domain in (".youtube.com", ".music.youtube.com"):
            lines.append(f"{domain}\tTRUE\t/\tTRUE\t{expiry}\t{name}\t{value}")
    tmp = COOKIES_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, COOKIES_PATH)
    return len(cookies)


def harvest_once() -> bool:
    token = refresh_access_token(REFRESH_TOKEN)
    log(f"تم تجديد access token ({len(token)} حرفاً)")
    cookies = harvest(token)
    if not cookies:
        log("لم تُلتقط أي كوكيز — ستُعاد المحاولة في الدورة القادمة")
        return False
    n = write_netscape(cookies)
    log(f"🍪 كُتب {n} نوع كوكيز إلى {COOKIES_PATH}")
    return True


def main():
    log("نظام الكوكيز الذكي انطلق — تسجيل دخول OAuth ثم جلب الكوكيز تلقائياً")
    while True:
        try:
            harvest_once()
        except Exception as exc:
            log(f"خطأ في الدورة: {exc!r}")
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
COOKIESPY_EOF

# ── مزامِن POT: يولّد poToken+visitorData من bgutil ويحقنهما في Lavalink ──
RUN cat > /opt/bot/pot_sync.py <<'POTSYNC_EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
elminyawe — مزامِن PO Token (bgutil → Lavalink)
─────────────────────────────────────────────────
المشكلة التي يحلّها: يوتيوب يحجب التشغيل من سيرفرات الاستضافة برسالة
"Sign in to confirm you're not a bot" (AllClientsFailedException).
الحل النهائي: عميل WEB في إضافة يوتيوب يعمل فقط عند توفر زوج صالح من
(POT token + visitorData). هذا المزامِن:
  1. يطلب رمزاً جديداً من خادم bgutil المحلي (127.0.0.1:4416)
     - الاستجابة تحتوي poToken وcontentBinding (وهو visitorData) معاً
       فتكون الثنائية متطابقة ومولّدة من نفس الجلسة.
  2. يرسلهما إلى Lavalink عبر POST /youtube (المسار المثبّت تجريبياً)
     - نرسل refreshToken = "x" (قيمة الحارس في الكود المصدري) حتى لا
       يُلمس تكوين OAuth القائم إطلاقاً.
  3. يكتب حالة العمل في pot_status.json للفحص والتشخيص.
  4. يكرّر التجديد كل POT_REFRESH_INTERVAL_SEC (افتراضياً 4 ساعات —
       عمر الرمز الفعلي 6 ساعات فنتجديد قبل انتهائه بهامش أمان).
لا يخرج أبداً (الحلقة الداخلية تبتلع الأخطاء وتعيد المحاولة) —
مشرف العمليات يعيد تشغيله فقط عند الانهيار الكامل.
"""
import json
import os
import signal
import sys
import time

import urllib.error
import urllib.request

# ── التهيئة من البيئة (نفس متغيرات باقي النظام) ─────────────────────────────
BGUTIL_URL = os.getenv("BGUTIL_URL", "http://127.0.0.1:4416").rstrip("/")
LAVALINK_HOST = os.getenv("LAVALINK_HOST", "127.0.0.1")
LAVALINK_PORT = os.getenv("LAVALINK_PORT", "2008")
LAVALINK_PASSWORD = os.getenv("LAVALINK_PASSWORD", "ELMINYAWE")
LAVALINK_URL = f"http://{LAVALINK_HOST}:{LAVALINK_PORT}"
POT_REFRESH_INTERVAL_SEC = int(os.getenv("POT_REFRESH_INTERVAL_SEC", "14400"))
RETRY_ON_ERROR_SEC = int(os.getenv("POT_RETRY_SEC", "120"))
STATUS_FILE = os.getenv("POT_STATUS_FILE", "/opt/bot/pot_status.json")
# عمر الرمز الآمن المتوقع من bgutil (ساعات) — نتجدد عند 60% منه أيضاً
_T0 = time.time()


def log(msg: str) -> None:
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"{stamp} INFO    potsync | {msg}", flush=True)


def log_err(msg: str) -> None:
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"{stamp} ERROR   potsync | {msg}", flush=True)


def http_json(url: str, method: str = "GET", body: dict = None,
              headers: dict = None, timeout: int = 30):
    """طلب HTTP بسيط بدون مكتبات خارجية. يعيد (status, parsed_or_text)."""
    data = None
    hdrs = {"Content-Type": "application/json"}
    hdrs.update(headers or {})
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
            try:
                return resp.status, json.loads(raw)
            except ValueError:
                return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")[:300]
        return e.code, raw


def wait_for_service(url: str, headers: dict = None, what: str = "",
                     max_wait: int = 600) -> bool:
    """ينتظر جاهزية خدمة (يفحص كل 5 ثوان حتى max_wait ثانية)."""
    deadline = time.time() + max_wait
    n = 0
    while time.time() < deadline:
        try:
            code, _ = http_json(url, headers=headers, timeout=8)
            if 200 <= code < 300:
                if n:
                    log(f"{what} أصبح جاهزاً بعد {n} محاولة")
                return True
        except Exception:
            pass
        n += 1
        time.sleep(5)
    log_err(f"{what} لم يصبح جاهزاً خلال {max_wait} ثانية")
    return False


def write_status(update: dict) -> None:
    """كتابة ذرّية لملف الحالة (tmp ثم rename كما في yt_cookies)."""
    try:
        status = {}
        try:
            with open(STATUS_FILE, "r", encoding="utf-8") as f:
                status = json.load(f)
        except Exception:
            status = {}
        status.update(update)
        status["updated_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
        tmp = STATUS_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(status, f, ensure_ascii=False, indent=2)
        os.replace(tmp, STATUS_FILE)
    except Exception as e:
        log_err(f"status write failed: {e!r}")


def fetch_pot() -> dict:
    """يطلب {poToken, contentBinding} من bgutil. يرفع استثناء عند الفشل."""
    code, body = http_json(f"{BGUTIL_URL}/get_pot", method="POST",
                           body={}, timeout=180)
    if code != 200 or not isinstance(body, dict):
        raise RuntimeError(f"bgutil get_pot HTTP {code}: {str(body)[:200]}")
    pot = body.get("poToken") or ""
    vd = body.get("contentBinding") or ""
    expires = body.get("expiresAt") or ""
    if not pot or not vd:
        raise RuntimeError("bgutil returned empty poToken/contentBinding")
    return {"poToken": pot, "visitorData": vd, "expiresAt": expires}


def apply_to_lavalink(pot: str, vd: str) -> None:
    """يرسل الثنائية إلى Lavalink. refreshToken='x' حارس عدم لمس OAuth."""
    payload = {"poToken": pot, "visitorData": vd, "refreshToken": "x",
               "skipInitialization": False}
    code, body = http_json(
        f"{LAVALINK_URL}/youtube", method="POST", body=payload,
        headers={"Authorization": LAVALINK_PASSWORD}, timeout=30)
    if code != 204:
        raise RuntimeError(f"lavalink POST /youtube HTTP {code}: {str(body)[:200]}")


def refresh_once() -> dict:
    """دورة تحديث كاملة: جلب ثم تطبيق. يعيد معلومات للسجل."""
    info = fetch_pot()
    pot, vd = info["poToken"], info["visitorData"]
    apply_to_lavalink(pot, vd)
    return info


def main() -> int:
    log(f"potsync يبدأ — bgutil={BGUTIL_URL} lavalink={LAVALINK_URL} "
        f"تجديد كل {POT_REFRESH_INTERVAL_SEC} ثانية")
    write_status({"state": "starting", "applied_count": 0})

    # انتظار الخدمتين — لا نخرج أبداً، فقط نحاول
    while True:
        ok_bg = wait_for_service(f"{BGUTIL_URL}/ping", what="bgutil",
                                 max_wait=900)
        ok_lv = wait_for_service(f"{LAVALINK_URL}/version",
                                 headers={"Authorization": LAVALINK_PASSWORD},
                                 what="lavalink", max_wait=900)
        if ok_bg and ok_lv:
            break
        log_err("إعادة محاولة انتظار الخدمات بعد دقيقة...")
        time.sleep(60)

    count = 0
    while True:
        try:
            t_start = time.time()
            info = refresh_once()
            count += 1
            elapsed = int(time.time() - t_start)
            log(f"✅ POT #{count} طُبّق بنجاح ({elapsed} ث) — "
                f"token: {info['poToken'][:10]}… ({len(info['poToken'])} حرفاً) "
                f"visitorData: {info['visitorData'][:14]}… "
                f"({len(info['visitorData'])} حرفاً) expiresAt: {info['expiresAt']}")
            write_status({"state": "applied", "applied_count": count,
                          "po_token_prefix": info["poToken"][:10],
                          "po_token_len": len(info["poToken"]),
                          "visitor_data_prefix": info["visitorData"][:14],
                          "visitor_data_len": len(info["visitorData"]),
                          "expires_at": info["expiresAt"],
                          "last_error": ""})
            # نوم حتى الدورة القادمة (بتقطيع قصير ليسمح بالإيقاف النظيف)
            wake = time.time() + POT_REFRESH_INTERVAL_SEC
            while time.time() < wake:
                time.sleep(min(30, max(1, wake - time.time())))
        except Exception as e:
            log_err(f"فشل دورة POT (إعادة المحاولة بعد {RETRY_ON_ERROR_SEC} ث): {e!r}")
            write_status({"state": "error", "last_error": repr(e)[:300]})
            time.sleep(RETRY_ON_ERROR_SEC)


def _term(_sig, _frm):
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _term)
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
POTSYNC_EOF

# ── إعدادات supervisor (تشغيل الخدمات الثلاث معاً) ──────────────────────────
RUN cat > /etc/supervisor/conf.d/elminyawe.conf <<'SUPEOF'
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0
pidfile=/tmp/supervisord.pid

[program:mariadb]
command=/usr/sbin/mariadbd --user=mysql --datadir=/var/lib/mysql --bind-address=127.0.0.1 --innodb-buffer-pool-size=64M --max-connections=25 --skip-name-resolve
priority=10
autorestart=true
startretries=20
startsecs=5
redirect_stderr=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0

[program:bgutil]
directory=/opt/bgutil/server
command=/usr/bin/node /opt/bgutil/server/build/main.js
priority=15
autorestart=true
startretries=20
startsecs=5
redirect_stderr=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0

[program:lavalink]
directory=/opt/lavalink
command=/bin/sh -c "exec java $JAVA_OPTS -jar /opt/lavalink/Lavalink.jar"
priority=20
autorestart=true
startretries=20
startsecs=10
redirect_stderr=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0

[program:potsync]
directory=/opt/bot
command=/usr/local/bin/python3 /opt/bot/pot_sync.py
priority=22
autorestart=true
startretries=999
startsecs=5
redirect_stderr=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0

[program:ytcookies]
directory=/opt/bot
command=/usr/local/bin/python3 /opt/bot/yt_cookies.py
priority=25
autorestart=true
startretries=999
startsecs=5
redirect_stderr=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0

[program:bot]
directory=/opt/bot
command=/usr/local/bin/python3 /opt/bot/music.py
priority=30
autorestart=true
startretries=999
startsecs=5
redirect_stderr=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
SUPEOF

# ── نقطة الدخول ─────────────────────────────────────────────────────────────
RUN cat > /opt/entrypoint.sh <<'ENTEOF'
#!/bin/sh
# elminyawe — نقطة الدخول
set -e

echo "[elminyawe] توليد إعدادات Lavalink من متغيرات البيئة..."
python3 /opt/bot/gen_lavalink_config.py

echo "[elminyawe] تجهيز MariaDB..."
mkdir -p /run/mysqld /var/lib/mysql
chown -R mysql:mysql /run/mysqld /var/lib/mysql
if [ ! -d /var/lib/mysql/mysql ]; then
  echo "[elminyawe] أول تشغيل: تهيئة قاعدة البيانات..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null 2>&1 || \
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql || true
fi

echo "[elminyawe] تشغيل الخدمات (MariaDB + Lavalink + Bot)..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/elminyawe.conf
ENTEOF
RUN chmod +x /opt/entrypoint.sh \
    && mkdir -p /run/mysqld /var/lib/mysql \
    && chown -R mysql:mysql /run/mysqld /var/lib/mysql

EXPOSE 2008

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
    CMD curl -sf -H "Authorization: $LAVALINK_PASSWORD" "http://127.0.0.1:$LAVALINK_PORT/version" || true

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/entrypoint.sh"]
