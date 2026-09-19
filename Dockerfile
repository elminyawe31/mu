# syntax=docker/dockerfile:1.7
# ═══════════════════════════════════════════════════════════════════════════
#  🎵 Music Discord Bot — ملف واحد شامل كل شيء (جاهز لـ GitHub + Railway)
# ─────────────────────────────────────────────────────────────────────────
#  هذا الملف هو المشروع بالكامل: كود البوت + Lavalink v4 + MariaDB.
#  لا يحتاج أي ملف آخر بجانبه إطلاقاً.
#
#  ▶ الخطوات على Railway:
#    1) أنشئ مستودع GitHub جديداً وضع هذا الملف باسم  Dockerfile
#       (حرف D كبير، بدون امتداد) في جذر المستودع.
#    2) Railway → New Project → Deploy from GitHub repo → اختر المستودع.
#    3) Railway سيبني الصورة ويشغّل كل شيء تلقائياً (لا حاجة لأي إعدادات).
#
#  ▶ تغيير التوكن مستقبلاً (اختر إحدى الطريقتين):
#    • الطريقة 1: عدّل سطر ENV DISCORD_TOKEN بالأسفل داخل هذا الملف ثم أعد النشر.
#    • الطريقة 2 (أسرع): Railway → خدمتك → Variables → أنشئ متغيراً باسم
#      DISCORD_TOKEN بقيمة التوكن الجديد — متغيرات Railway تتغلب على القيمة
#      المكتوبة داخل الملف دون الحاجة لتعديله.
#
#  ▶ المنفذ 2333 (Lavalink) داخلي 100%:
#    يستمع على 127.0.0.1 داخل الحاوية ولا يُفتح للإنترنت إطلاقاً — البوت
#    يتحدث معه محلياً فقط، لذلك لا يوجد أي منفذ عام في Railway.
#
#  ▶ ثبات الصوت (حل مشكلة انقطاع خوادم Lavalink الخارجية):
#    • Lavalink يعمل داخل نفس الحاوية — لا خوادم خارجية تنقطع أبداً.
#    • استئناف جلسة تلقائي (session resuming) عند أي وميض شبكة.
#    • مراقب داخلي في البوت يعيد بناء المشغل ويكمل الأغنية من نفس الثانية
#      إذا أُعيد تشغيل Lavalink.
#    • مشرف على مستوى الحاوية يعيد تشغيل Lavalink/MariaDB تلقائياً إذا توقفوا.
#    • البوت نفسه يعاد تشغيله تلقائياً مع backoff عند أي انهيار.
#
#  ▶ التشغيل المحلي (اختياري):
#      docker build -t musicbot .
#      docker run -d --name musicbot --restart unless-stopped musicbot
#
#  ▶ متغيرات بيئة اختيارية (كلها لها قيم افتراضية جاهزة):
#      LAVALINK_HEAP=512m        ذاكرة Lavalink (قلّلها إلى 256m إذا كانت
#                                خطة Railway محدودة الذاكرة)
#      PREFIX=?                  بادئة الأوامر النصية
#      SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET   لتفعيل روابط Spotify
#      DEEZER_ENABLED=true + DEEZER_MASTER_KEY=...   لتفعيل Deezer (اختياري)
#      AUTO_DISCONNECT_SECONDS=300   خروج تلقائي عند الخمول (0 = تعطيل)
# ═══════════════════════════════════════════════════════════════════════════

FROM python:3.12-bookworm

# ─────────────── Java 21 (Temurin) + أدوات النظام ───────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget gpg apt-transport-https ca-certificates curl tini procps tzdata \
    && mkdir -p /etc/apt/keyrings \
    && wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
        | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo $VERSION_CODENAME) main" \
        > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update && apt-get install -y --no-install-recommends temurin-21-jre \
    && apt-get purge -y wget gpg \
    && rm -rf /var/lib/apt/lists/*

# ─────────────── MariaDB server ───────────────
RUN apt-get update \
    && apt-get install -y --no-install-recommends mariadb-server \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# ─────────────── Lavalink 4.2.2 + الإضافات (تحميل مسبق أثناء البناء) ───────────────
RUN mkdir -p /opt/lavalink/plugins /opt/lavalink/logs \
    && curl -fsSL -o /opt/lavalink/Lavalink.jar \
        "https://github.com/lavalink-devs/Lavalink/releases/download/4.2.2/Lavalink.jar" \
    && curl -fsSL -o /opt/lavalink/plugins/youtube-plugin-1.18.2.jar \
        "https://maven.lavalink.dev/releases/dev/lavalink/youtube/youtube-plugin/1.18.2/youtube-plugin-1.18.2.jar" \
    && curl -fsSL -o /opt/lavalink/plugins/lavasrc-plugin-4.8.3.jar \
        "https://maven.lavalink.dev/releases/com/github/topi314/lavasrc/lavasrc-plugin/4.8.3/lavasrc-plugin-4.8.3.jar" \
    && chmod 755 /opt/lavalink/Lavalink.jar

# ─────────────── مكتبات البوت (مدمجة داخل الملف) ───────────────
WORKDIR /app
COPY <<'ZEOF_REQUIREMENTS' /tmp/requirements.txt
discord.py==2.7.1
wavelink==3.5.2
aiomysql==0.3.2
aiosqlite==0.20.0
PyNaCl==1.6.2
davey==0.1.6
python-dotenv==1.0.1
ZEOF_REQUIREMENTS


RUN pip install --no-cache-dir -r /tmp/requirements.txt

# ─────────────── كود البوت الكامل (مدمج داخل الملف) ───────────────
COPY <<'ZEOF_CONFIG_PY' /app/config.py
"""
Hybrid configuration loader.

Priority: environment variables > .env file > built-in defaults.

This makes the bot work everywhere:
  - Docker (all-in-one): everything comes from environment variables.
  - Local run: create a `.env` file next to main.py (see .env.example).
"""

import os

from dotenv import load_dotenv

# Loads .env from the current working directory if present.
# Existing environment variables are NEVER overridden by .env (hybrid behaviour).
load_dotenv(override=False)


def _get(key: str, default: str = "") -> str:
    value = os.getenv(key)
    if value is None or value.strip() == "":
        return default
    return value.strip()


def _get_int(key: str, default: int) -> int:
    try:
        return int(_get(key, str(default)))
    except ValueError:
        return default


def _get_bool(key: str, default: bool = False) -> bool:
    raw = _get(key, "1" if default else "0").lower()
    return raw in ("1", "true", "yes", "on", "enabled")


class Config:
    """All runtime configuration in one place."""

    # ------------------------------------------------------------- Discord
    # Accepts DISCORD_TOKEN (preferred) or BOT_TOKEN (legacy name).
    DISCORD_TOKEN: str = _get("DISCORD_TOKEN", _get("BOT_TOKEN"))
    PREFIX: str = _get("PREFIX", "?")
    ACTIVITY: str = _get("ACTIVITY", "music | /play")

    # ----------------------------------------------------------- Lavalink
    LAVALINK_HOST: str = _get("LAVALINK_HOST", "127.0.0.1")
    LAVALINK_PORT: int = _get_int("LAVALINK_PORT", 2333)
    LAVALINK_PASSWORD: str = _get("LAVALINK_PASSWORD", "youshallnotpass")
    # Seconds of inactivity (nobody listening / nothing playing) before the
    # bot leaves the voice channel. 0 disables the auto-disconnect.
    AUTO_DISCONNECT_SECONDS: int = _get_int("AUTO_DISCONNECT_SECONDS", 300)

    # ----------------------------------------------------------- Database
    # DB_TYPE: "mysql" (MariaDB/MySQL - used by the all-in-one Docker image)
    # or "sqlite" (single file - easy local runs without any database server).
    DB_TYPE: str = _get("DB_TYPE", "mysql").lower()
    DB_HOST: str = _get("DB_HOST", "127.0.0.1")
    DB_PORT: int = _get_int("DB_PORT", 3306)
    DB_USER: str = _get("DB_USER", "musicbot")
    DB_PASSWORD: str = _get("DB_PASSWORD", "musicbotpass")
    DB_NAME: str = _get("DB_NAME", "musicbot")
    SQLITE_PATH: str = _get("SQLITE_PATH", "musicbot.sqlite3")

    # ------------------------------------------------------------ Playback
    DEFAULT_VOLUME: int = _get_int("DEFAULT_VOLUME", 60)
    MAX_VOLUME: int = _get_int("MAX_VOLUME", 150)

    # ------------------------------------------------- Development/testing
    # Provide a guild ID to sync slash commands instantly to that server
    # (global slash sync can take up to one hour to propagate).
    TEST_GUILD_ID: "int | None" = (
        _get_int("TEST_GUILD_ID", 0) or None
    )
    # Internal flag used by Scripts/auto_test.py to run the end-to-end test.
    AUTOTEST: bool = _get_bool("AUTOTEST", False)
    # Optional: name of the voice channel the auto-test should join.
    TEST_VOICE_CHANNEL: str = _get("TEST_VOICE_CHANNEL", "")

    @classmethod
    def validate(cls) -> "list[str]":
        """Return a list of configuration problems (empty list = OK)."""
        problems: "list[str]" = []
        if not cls.DISCORD_TOKEN:
            problems.append(
                "DISCORD_TOKEN is missing. Set it as an environment variable "
                "or inside a .env file (see .env.example)."
            )
        if cls.DB_TYPE not in ("mysql", "sqlite"):
            problems.append(
                f"DB_TYPE must be 'mysql' or 'sqlite' (got: {cls.DB_TYPE})."
            )
        if cls.AUTO_DISCONNECT_SECONDS < 0:
            problems.append("AUTO_DISCONNECT_SECONDS must be >= 0.")
        if not 1 <= cls.DEFAULT_VOLUME <= cls.MAX_VOLUME:
            problems.append(
                f"DEFAULT_VOLUME must be between 1 and {cls.MAX_VOLUME}."
            )
        return problems
ZEOF_CONFIG_PY
COPY <<'ZEOF_DATABASE_PY' /app/database.py
"""
Async database layer with two interchangeable backends:

  - ``mysql``  -> MariaDB/MySQL through aiomysql (used by the all-in-one Docker image)
  - ``sqlite`` -> a single file through aiosqlite (zero-setup local runs)

Both backends expose exactly the same interface, and the schema is created
automatically on startup (no manual SQL import needed).
"""

from __future__ import annotations

import json
import logging
from typing import Any, Optional

import aiomysql
import aiosqlite

from config import Config

log = logging.getLogger("musicbot.database")

SCHEMA_SQL = {
    "servers": """
        CREATE TABLE IF NOT EXISTS servers (
            server_id BIGINT PRIMARY KEY,
            volume    INT NOT NULL DEFAULT 60,
            settings  TEXT
        )
    """,
    "queue_tracks": """
        CREATE TABLE IF NOT EXISTS queue_tracks (
            id           {PK},
            server_id    BIGINT NOT NULL,
            position     INT NOT NULL,
            track_data   TEXT NOT NULL,
            requester_id BIGINT,
            INDEX idx_queue_server (server_id, position)
        )
    """.replace("{PK}", "BIGINT AUTO_INCREMENT PRIMARY KEY"),
    "playlists": """
        CREATE TABLE IF NOT EXISTS playlists (
            id         {PK},
            server_id  BIGINT NOT NULL,
            name       VARCHAR(100) NOT NULL,
            creator_id BIGINT,
            UNIQUE KEY uq_playlist (server_id, name)
        )
    """.replace("{PK}", "BIGINT AUTO_INCREMENT PRIMARY KEY"),
    "playlist_tracks": """
        CREATE TABLE IF NOT EXISTS playlist_tracks (
            id           {PK},
            playlist_id  BIGINT NOT NULL,
            position     INT NOT NULL,
            track_data   TEXT NOT NULL,
            INDEX idx_ptracks (playlist_id, position)
        )
    """.replace("{PK}", "BIGINT AUTO_INCREMENT PRIMARY KEY"),
}

# SQLite does not support the MySQL "INDEX ... ()" inline syntax.
SCHEMA_SQL_SQLITE = {
    "servers": """
        CREATE TABLE IF NOT EXISTS servers (
            server_id INTEGER PRIMARY KEY,
            volume    INTEGER NOT NULL DEFAULT 60,
            settings  TEXT
        )
    """,
    "queue_tracks": """
        CREATE TABLE IF NOT EXISTS queue_tracks (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id    INTEGER NOT NULL,
            position     INTEGER NOT NULL,
            track_data   TEXT NOT NULL,
            requester_id INTEGER
        )
    """,
    "playlists": """
        CREATE TABLE IF NOT EXISTS playlists (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id  INTEGER NOT NULL,
            name       TEXT NOT NULL,
            creator_id INTEGER,
            UNIQUE (server_id, name)
        )
    """,
    "playlist_tracks": """
        CREATE TABLE IF NOT EXISTS playlist_tracks (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            playlist_id  INTEGER NOT NULL,
            position     INTEGER NOT NULL,
            track_data   TEXT NOT NULL
        )
    """,
}


class Database:
    """Unified async database interface (MySQL or SQLite)."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self._pool: "Optional[aiomysql.Pool]" = None
        self._sqlite: "Optional[aiosqlite.Connection]" = None

    # ------------------------------------------------------------- setup
    async def init(self) -> None:
        if self.cfg.DB_TYPE == "mysql":
            self._pool = await aiomysql.create_pool(
                host=self.cfg.DB_HOST,
                port=self.cfg.DB_PORT,
                user=self.cfg.DB_USER,
                password=self.cfg.DB_PASSWORD,
                db=self.cfg.DB_NAME,
                autocommit=True,
                minsize=1,
                maxsize=5,
                loop=None,
            )
            log.info("Connected to MariaDB at %s:%s/%s",
                     self.cfg.DB_HOST, self.cfg.DB_PORT, self.cfg.DB_NAME)
            async with self._pool.acquire() as conn:
                async with conn.cursor() as cur:
                    for stmt in SCHEMA_SQL.values():
                        await cur.execute(stmt)
        else:
            self._sqlite = await aiosqlite.connect(self.cfg.SQLITE_PATH)
            self._sqlite.row_factory = aiosqlite.Row
            log.info("Connected to SQLite database at %s", self.cfg.SQLITE_PATH)
            for stmt in SCHEMA_SQL_SQLITE.values():
                await self._sqlite.execute(stmt)
            await self._sqlite.commit()
        log.info("Database schema verified (all tables present).")

    async def close(self) -> None:
        if self._pool is not None:
            self._pool.close()
            await self._pool.wait_closed()
        if self._sqlite is not None:
            await self._sqlite.close()

    # --------------------------------------------------------- internals
    async def _fetchall(self, query: str, args: tuple = ()) -> "list[tuple]":
        if self._pool is not None:
            async with self._pool.acquire() as conn:
                async with conn.cursor() as cur:
                    await cur.execute(query, args)
                    return list(await cur.fetchall())
        async with self._sqlite.execute(query, args) as cur:
            return list(await cur.fetchall())

    async def _execute(self, query: str, args: tuple = ()) -> None:
        if self._pool is not None:
            async with self._pool.acquire() as conn:
                async with conn.cursor() as cur:
                    await cur.execute(query, args)
        else:
            await self._sqlite.execute(query, args)
            await self._sqlite.commit()

    # -------------------------------------------------------- servers
    async def upsert_server(self, server_id: int) -> None:
        await self._execute(
            "INSERT IGNORE INTO servers (server_id, volume) VALUES (%s, %s)"
            if self._pool is not None else
            "INSERT OR IGNORE INTO servers (server_id, volume) VALUES (?, ?)",
            (server_id, self.cfg.DEFAULT_VOLUME),
        )

    async def get_volume(self, server_id: int) -> Optional[int]:
        rows = await self._fetchall(
            "SELECT volume FROM servers WHERE server_id = %s"
            if self._pool is not None else
            "SELECT volume FROM servers WHERE server_id = ?",
            (server_id,),
        )
        return int(rows[0][0]) if rows else None

    async def set_volume(self, server_id: int, volume: int) -> None:
        await self.upsert_server(server_id)
        await self._execute(
            "UPDATE servers SET volume = %s WHERE server_id = %s"
            if self._pool is not None else
            "UPDATE servers SET volume = ? WHERE server_id = ?",
            (volume, server_id),
        )

    # ---------------------------------------------------------- queue
    async def replace_queue(self, server_id: int, tracks: "list[dict]") -> None:
        """Persist the in-memory queue (source of truth = memory)."""
        await self._execute(
            "DELETE FROM queue_tracks WHERE server_id = %s"
            if self._pool is not None else
            "DELETE FROM queue_tracks WHERE server_id = ?",
            (server_id,),
        )
        for position, item in enumerate(tracks):
            await self._execute(
                "INSERT INTO queue_tracks (server_id, position, track_data, requester_id) "
                "VALUES (%s, %s, %s, %s)"
                if self._pool is not None else
                "INSERT INTO queue_tracks (server_id, position, track_data, requester_id) "
                "VALUES (?, ?, ?, ?)",
                (server_id, position, json.dumps(item["data"]), item["requester"]),
            )

    async def get_queue(self, server_id: int) -> "list[dict]":
        rows = await self._fetchall(
            "SELECT track_data, requester_id FROM queue_tracks WHERE server_id = %s "
            "ORDER BY position ASC"
            if self._pool is not None else
            "SELECT track_data, requester_id FROM queue_tracks WHERE server_id = ? "
            "ORDER BY position ASC",
            (server_id,),
        )
        result: "list[dict]" = []
        for row in rows:
            try:
                result.append({
                    "data": json.loads(row[0]),
                    "requester": row[1],
                })
            except (json.JSONDecodeError, TypeError):
                continue
        return result

    async def queue_count(self, server_id: int) -> int:
        rows = await self._fetchall(
            "SELECT COUNT(*) FROM queue_tracks WHERE server_id = %s"
            if self._pool is not None else
            "SELECT COUNT(*) FROM queue_tracks WHERE server_id = ?",
            (server_id,),
        )
        return int(rows[0][0]) if rows else 0

    # ------------------------------------------------------ playlists
    async def playlist_create(self, server_id: int, name: str,
                              creator_id: int) -> bool:
        """Returns False if a playlist with this name already exists."""
        existing = await self._fetchall(
            "SELECT id FROM playlists WHERE server_id = %s AND name = %s"
            if self._pool is not None else
            "SELECT id FROM playlists WHERE server_id = ? AND name = ?",
            (server_id, name),
        )
        if existing:
            return False
        await self._execute(
            "INSERT INTO playlists (server_id, name, creator_id) VALUES (%s, %s, %s)"
            if self._pool is not None else
            "INSERT INTO playlists (server_id, name, creator_id) VALUES (?, ?, ?)",
            (server_id, name, creator_id),
        )
        return True

    async def playlist_delete(self, server_id: int, name: str) -> bool:
        rows = await self._fetchall(
            "SELECT id FROM playlists WHERE server_id = %s AND name = %s"
            if self._pool is not None else
            "SELECT id FROM playlists WHERE server_id = ? AND name = ?",
            (server_id, name),
        )
        if not rows:
            return False
        playlist_id = int(rows[0][0])
        await self._execute(
            "DELETE FROM playlist_tracks WHERE playlist_id = %s"
            if self._pool is not None else
            "DELETE FROM playlist_tracks WHERE playlist_id = ?",
            (playlist_id,),
        )
        await self._execute(
            "DELETE FROM playlists WHERE id = %s"
            if self._pool is not None else
            "DELETE FROM playlists WHERE id = ?",
            (playlist_id,),
        )
        return True

    async def playlist_list(self, server_id: int) -> "list[tuple[int, str, int]]":
        rows = await self._fetchall(
            "SELECT p.id, p.name, COUNT(t.id) FROM playlists p "
            "LEFT JOIN playlist_tracks t ON t.playlist_id = p.id "
            "WHERE p.server_id = %s GROUP BY p.id, p.name ORDER BY p.name"
            if self._pool is not None else
            "SELECT p.id, p.name, COUNT(t.id) FROM playlists p "
            "LEFT JOIN playlist_tracks t ON t.playlist_id = p.id "
            "WHERE p.server_id = ? GROUP BY p.id, p.name ORDER BY p.name",
            (server_id,),
        )
        return [(int(r[0]), str(r[1]), int(r[2])) for r in rows]

    async def playlist_get(self, server_id: int, name: str) -> "Optional[dict]":
        rows = await self._fetchall(
            "SELECT id FROM playlists WHERE server_id = %s AND name = %s"
            if self._pool is not None else
            "SELECT id FROM playlists WHERE server_id = ? AND name = ?",
            (server_id, name),
        )
        if not rows:
            return None
        return {"id": int(rows[0][0]), "name": name}

    async def playlist_add_tracks(self, playlist_id: int,
                                  tracks: "list[dict]") -> int:
        rows = await self._fetchall(
            "SELECT COALESCE(MAX(position), -1) FROM playlist_tracks WHERE playlist_id = %s"
            if self._pool is not None else
            "SELECT COALESCE(MAX(position), -1) FROM playlist_tracks WHERE playlist_id = ?",
            (playlist_id,),
        )
        start = int(rows[0][0]) + 1 if rows else 0
        for offset, item in enumerate(tracks):
            await self._execute(
                "INSERT INTO playlist_tracks (playlist_id, position, track_data) "
                "VALUES (%s, %s, %s)"
                if self._pool is not None else
                "INSERT INTO playlist_tracks (playlist_id, position, track_data) "
                "VALUES (?, ?, ?)",
                (playlist_id, start + offset, json.dumps(item["data"])),
            )
        return len(tracks)

    async def playlist_get_tracks(self, playlist_id: int) -> "list[dict]":
        rows = await self._fetchall(
            "SELECT track_data FROM playlist_tracks WHERE playlist_id = %s "
            "ORDER BY position ASC"
            if self._pool is not None else
            "SELECT track_data FROM playlist_tracks WHERE playlist_id = ? "
            "ORDER BY position ASC",
            (playlist_id,),
        )
        result: "list[dict]" = []
        for row in rows:
            try:
                result.append({"data": json.loads(row[0]), "requester": None})
            except (json.JSONDecodeError, TypeError):
                continue
        return result
ZEOF_DATABASE_PY
COPY <<'ZEOF_MAIN_PY' /app/main.py
#!/usr/bin/env python3
"""
Music Discord Bot - v2 (fully upgraded).

Stack: discord.py 2.7 + wavelink 3.5 + Lavalink v4 (+ youtube-source & LavaSrc
plugins) + MariaDB/SQLite.

Run:  python main.py          (configure via .env or environment variables)
"""

from __future__ import annotations

import asyncio
import logging
import sys

import discord
import wavelink
from discord.ext import commands

from config import Config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logging.getLogger("wavelink").setLevel(logging.INFO)

log = logging.getLogger("musicbot")


class MusicBot(commands.Bot):
    def __init__(self, cfg: Config, enable_prefix_commands: bool = True):
        self.cfg = cfg
        self.enable_prefix_commands = enable_prefix_commands

        intents = discord.Intents.default()
        intents.voice_states = True
        if enable_prefix_commands:
            # Privileged intent - must be enabled in the Developer Portal.
            # If it is not, we retry without it (slash-only mode).
            intents.message_content = True

        super().__init__(
            command_prefix=cfg.PREFIX if enable_prefix_commands else commands.when_mentioned,
            intents=intents,
            help_command=None,
        )
        self.music = None  # type: ignore[assignment]
        self.db = None  # type: ignore[assignment]
        self.node_watchdog_task: "asyncio.Task | None" = None
        # Songs already rescued via SoundCloud (prevents rescue loops).
        self._rescued: set = set()

    # ------------------------------------------------------------ startup
    async def setup_hook(self) -> None:
        # 1. Database ------------------------------------------------------
        from database import Database

        self.db = Database(self.cfg)
        await self.db.init()

        # 2. Lavalink ------------------------------------------------------
        timeout = (self.cfg.AUTO_DISCONNECT_SECONDS
                   if self.cfg.AUTO_DISCONNECT_SECONDS > 0 else None)
        node = wavelink.Node(
            identifier="MAIN",
            uri=f"http://{self.cfg.LAVALINK_HOST}:{self.cfg.LAVALINK_PORT}",
            password=self.cfg.LAVALINK_PASSWORD,
            inactive_player_timeout=timeout,
        )
        try:
            await wavelink.Pool.connect(client=self, nodes=[node])
            log.info("Connected to Lavalink node at %s:%s",
                     self.cfg.LAVALINK_HOST, self.cfg.LAVALINK_PORT)
        except Exception as error:  # noqa: BLE001
            # Do not kill the whole bot: the watchdog task below keeps
            # retrying in the background until Lavalink is reachable.
            log.error("Initial Lavalink connection failed: %s - the node "
                      "watchdog will keep retrying.", error)
        self.node_watchdog_task = asyncio.create_task(self._node_watchdog())

        # 3. Cogs & persistent views ---------------------------------------
        from music import MusicCog
        from views import NowPlayingView

        await self.add_cog(MusicCog(self))
        self.music = self.get_cog("MusicCog")
        self.add_view(NowPlayingView(self))

        # 4. Slash command sync -------------------------------------------
        if self.cfg.TEST_GUILD_ID is not None:
            guild = discord.Object(id=self.cfg.TEST_GUILD_ID)
            self.tree.copy_global_to(guild=guild)
            await self.tree.sync(guild=guild)
            log.info("Slash commands synced instantly to guild %s",
                     self.cfg.TEST_GUILD_ID)
        else:
            synced = await self.tree.sync()
            log.info("Synced %s global slash commands (may take up to 1h "
                     "to appear everywhere).", len(synced))

    # ------------------------------------------------------------ events
    async def on_ready(self) -> None:
        await self.change_presence(
            activity=discord.Activity(type=discord.ActivityType.listening,
                                      name=self.cfg.ACTIVITY))
        log.info("=" * 60)
        log.info("Logged in as %s (id=%s)", self.user, getattr(self.user, "id", "?"))
        log.info("Prefix commands: %s | Slash commands: ready",
                 "ON" if self.enable_prefix_commands else "OFF (slash-only)")
        log.info("Connected to %s guild(s): %s",
                 len(self.guilds),
                 ", ".join(f"{g.name}({g.id})" for g in self.guilds) or "none")
        log.info("=" * 60)

        if self.cfg.AUTOTEST:
            asyncio.create_task(self._run_autotest())

    async def on_command_error(self, ctx: commands.Context, error: Exception) -> None:
        if isinstance(error, commands.CommandNotFound):
            return
        if isinstance(error, commands.MissingRequiredArgument):
            await ctx.send(f"Missing argument: `{error.param.name}`. "
                           f"Try `{self.cfg.PREFIX}help`.")
            return
        log.error("Command error in %s: %s", ctx.command, error, exc_info=error)

    async def _node_watchdog(self) -> None:
        """Keep at least one Lavalink node connected at all times.

        Wavelink already retries websocket connections on its own (with
        backoff) and requests session resuming - this watchdog is the last
        line of defence: if no node reports CONNECTED for two consecutive
        checks (~60s), it tears down the dead node objects and registers a
        fresh one. This is what prevents the classic "bot stays in the voice
        channel but goes silent forever" failure mode.
        """
        await self.wait_until_ready()
        failure_streak = 0
        while not self.is_closed():
            await asyncio.sleep(30)
            try:
                nodes = dict(wavelink.Pool.nodes)
                connected = [n for n in nodes.values()
                             if n.status == wavelink.NodeStatus.CONNECTED]
                if connected:
                    failure_streak = 0
                    continue
                failure_streak += 1
                if failure_streak < 2:
                    # Give wavelink's internal retry loop (backoff up to 30s)
                    # a chance to reconnect by itself before we intervene.
                    continue
                log.warning("Node watchdog: no connected Lavalink node - "
                            "rebuilding it.")
                failure_streak = 0
                pool_nodes = getattr(wavelink.Pool, "_Pool__nodes", {})
                for identifier in list(nodes):
                    try:
                        pool_nodes.pop(identifier, None)
                    except Exception:  # noqa: BLE001
                        pass
                timeout = (self.cfg.AUTO_DISCONNECT_SECONDS
                           if self.cfg.AUTO_DISCONNECT_SECONDS > 0 else None)
                node = wavelink.Node(
                    identifier=f"MAIN-{int(asyncio.get_running_loop().time())}",
                    uri=f"http://{self.cfg.LAVALINK_HOST}:"
                        f"{self.cfg.LAVALINK_PORT}",
                    password=self.cfg.LAVALINK_PASSWORD,
                    inactive_player_timeout=timeout,
                )
                await wavelink.Pool.connect(client=self, nodes=[node])
                log.info("Node watchdog: reconnected to Lavalink.")
            except asyncio.CancelledError:  # noqa: UP037
                raise
            except Exception as error:  # noqa: BLE001
                log.error("Node watchdog: reconnect failed: %s", error)

    async def _run_autotest(self) -> None:
        """Optional end-to-end test (AUTOTEST=1) - see Scripts/auto_test.py."""
        from Scripts.auto_test import run_auto_test

        try:
            await run_auto_test(self)
        except Exception:
            log.exception("Auto test crashed")


async def detect_message_content_intent(token: str) -> bool:
    """Probe the Discord gateway to see if the Message Content intent works.

    Returns True if the bot may use prefix commands, False if the privileged
    intent is disabled in the Developer Portal (slash-only mode then).
    Raises discord.errors.LoginFailure for an invalid token.
    """
    intents = discord.Intents.default()
    intents.message_content = True
    client = discord.Client(intents=intents)
    holder: dict = {}

    async def runner():
        try:
            await client.start(token)
        except Exception as error:  # noqa: BLE001 - probe collects everything
            holder["error"] = error

    task = asyncio.create_task(runner())
    ready = asyncio.create_task(client.wait_until_ready())
    done, _ = await asyncio.wait({task, ready}, timeout=25.0,
                                 return_when=asyncio.FIRST_COMPLETED)

    error = holder.get("error")
    if isinstance(error, discord.errors.LoginFailure):
        raise error

    connected = ready in done and not client.is_closed()
    try:
        await client.close()
    except Exception:  # noqa: BLE001
        pass
    task.cancel()
    return connected


def run() -> int:
    problems = Config.validate()
    if problems:
        print("Configuration problems found:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 2

    async def amain() -> int:
        try:
            prefix_ok = await detect_message_content_intent(Config.DISCORD_TOKEN)
        except discord.errors.LoginFailure:
            print("ERROR: The Discord token is invalid or was reset. Get a "
                  "fresh token from the Developer Portal.", file=sys.stderr)
            return 4
        except asyncio.TimeoutError:
            print("WARNING: Could not reach Discord to probe intents - "
                  "assuming prefix commands are allowed.", file=sys.stderr)
            prefix_ok = True

        if not prefix_ok:
            print("MESSAGE CONTENT INTENT is not enabled for this bot - "
                  "running in SLASH-ONLY mode.", file=sys.stderr)
            print("To enable prefix commands: Developer Portal -> your app -> "
                  "Bot -> Privileged Gateway Intents -> MESSAGE CONTENT INTENT.",
                  file=sys.stderr)

        bot = MusicBot(Config, enable_prefix_commands=prefix_ok)
        try:
            await bot.start(Config.DISCORD_TOKEN)
        except discord.errors.PrivilegedIntentsRequired:
            print("ERROR: Privileged intents are missing. Enable "
                  "'MESSAGE CONTENT INTENT' and 'SERVER MEMBERS INTENT' at "
                  "https://discord.com/developers/applications -> Bot.",
                  file=sys.stderr)
            return 3
        except KeyboardInterrupt:
            pass
        return 0

    try:
        return asyncio.run(amain())
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(run())
ZEOF_MAIN_PY
COPY <<'ZEOF_MUSIC_PY' /app/music.py
"""
The MusicCog: every music command (prefix `?play` AND slash `/play` in one
implementation via hybrid commands), plus playback event handling.
"""

from __future__ import annotations

import asyncio
import logging
import re
import time
from typing import Optional

import discord
import wavelink
from discord import app_commands
from discord.ext import commands

from config import Config
from database import Database
from views import NowPlayingView, SearchView, build_now_playing_embed, format_time

log = logging.getLogger("musicbot.music")

URL_REGEX = re.compile(r"https?://\S+", re.IGNORECASE)

# Maps user-facing source names to Lavalink search prefixes.
SOURCE_MAP = {
    "yt": wavelink.TrackSource.YouTube,
    "youtube": wavelink.TrackSource.YouTube,
    "ytm": wavelink.TrackSource.YouTubeMusic,
    "music": wavelink.TrackSource.YouTubeMusic,
    "sc": wavelink.TrackSource.SoundCloud,
    "soundcloud": wavelink.TrackSource.SoundCloud,
    "sp": "spsearch",          # LavaSrc (Spotify)
    "spotify": "spsearch",     # LavaSrc (Spotify)
    "dz": "dzsearch",          # LavaSrc (Deezer)
    "deezer": "dzsearch",      # LavaSrc (Deezer)
}


class MusicCog(commands.Cog):
    """All music playback logic and commands."""

    def __init__(self, bot):
        self.bot = bot
        self.cfg: Config = bot.cfg
        self.db: Database = bot.db
        # Per-guild text channel used for announcements (now playing, errors...).
        self.announce_channels: dict[int, discord.abc.Messageable] = {}
        # Live playback state per guild (used to recover players when the
        # Lavalink node loses its session, e.g. after a restart or downtime).
        self._live: "dict[int, dict]" = {}
        # Guards against concurrent player-recovery runs (two nodes coming
        # back at once must not fight over the same voice connection).
        self._recovering: bool = False

    # ================================================================== helpers
    async def _ensure_voice_core(self, guild: discord.Guild,
                                 member: discord.abc.User,
                                 respond) -> "Optional[wavelink.Player]":
        """Make sure the member is in a voice channel and the bot is connected.

        ``respond(text)`` is used for error messages (works for both prefix
        contexts and interactions).
        """
        if not isinstance(member, discord.Member):
            await respond("Could not resolve your voice state.")
            return None

        voice_state = member.voice
        if voice_state is None or voice_state.channel is None:
            await respond("Join a voice channel first!")
            return None

        channel = voice_state.channel
        existing = guild.voice_client

        if isinstance(existing, wavelink.Player):
            if existing.channel and existing.channel.id != channel.id:
                await existing.move_to(channel)
            return existing

        permissions = channel.permissions_for(guild.me)
        if not permissions.connect or not permissions.speak:
            await respond("I need **Connect** and **Speak** permissions in that channel.")
            return None

        try:
            player: wavelink.Player = await channel.connect(
                cls=wavelink.Player, self_deaf=True, timeout=20.0)
        except (discord.ClientException, wavelink.ChannelTimeoutException) as error:
            log.warning("Voice connect failed in %s: %s", guild.id, error)
            await respond("Could not connect to the voice channel. Try again.")
            return None

        stored_volume = await self.db.get_volume(guild.id)
        await player.set_volume(stored_volume if stored_volume is not None
                                else self.cfg.DEFAULT_VOLUME)
        return player

    async def ensure_voice(self, ctx: commands.Context) -> "Optional[wavelink.Player]":
        if ctx.guild is None:
            await ctx.send("This command only works inside a server.", ephemeral=True)
            return None

        async def respond(text: str):
            await ctx.send(text, ephemeral=True)

        return await self._ensure_voice_core(ctx.guild, ctx.author, respond)

    async def ensure_voice_itx(self, itx: discord.Interaction) -> "Optional[wavelink.Player]":
        if itx.guild is None:
            await itx.followup.send("This command only works inside a server.",
                                    ephemeral=True)
            return None

        async def respond(text: str):
            await itx.followup.send(text, ephemeral=True)

        return await self._ensure_voice_core(itx.guild, itx.user, respond)

    async def fetch_tracks(self, query: str, source_key: "Optional[str]" = None
                           ) -> "tuple[list[wavelink.Playable], Optional[str]]":
        """Search for tracks. Returns (tracks, playlist_name).

        YouTube blocks many datacenter IPs ("This video requires login"), so
        if the YouTube/YouTubeMusic search fails or returns nothing we fall
        back to SoundCloud automatically."""
        is_url = bool(URL_REGEX.match(query))
        explicit = bool(source_key and source_key.lower() in SOURCE_MAP)

        if explicit:
            source = SOURCE_MAP[source_key.lower()]
            results = await wavelink.Playable.search(query, source=source)
        elif is_url:
            results = await wavelink.Playable.search(query)
        else:
            try:
                results = await wavelink.Playable.search(
                    query, source=wavelink.TrackSource.YouTubeMusic)
            except Exception as error:
                log.warning("YouTube search failed (%s) - falling back to "
                            "SoundCloud.", error)
                results = await wavelink.Playable.search(
                    query, source=wavelink.TrackSource.SoundCloud)
            else:
                found = list(results.tracks if isinstance(results, wavelink.Playlist)
                             else (results or []))
                if not found:
                    log.info("YouTube search empty - falling back to "
                             "SoundCloud.")
                    results = await wavelink.Playable.search(
                        query, source=wavelink.TrackSource.SoundCloud)

        if isinstance(results, wavelink.Playlist):
            return list(results.tracks), results.name
        return list(results or [])[:15], None

    @staticmethod
    def track_snapshot(track: wavelink.Playable, requester: "Optional[int]") -> dict:
        return {"data": track.raw_data, "requester": requester}

    async def persist_queue(self, player: wavelink.Player) -> None:
        """Write the current in-memory queue to the database."""
        try:
            guild_id = player.guild.id
        except AttributeError:
            return
        items = [
            {"data": track.raw_data, "requester": None}
            for track in list(player.queue)
        ]
        await self.db.replace_queue(guild_id, items)

    async def restore_queue(self, player: wavelink.Player) -> int:
        """Restore a persisted queue after a restart (only if memory is empty)."""
        if player.queue.count > 0:
            return 0
        saved = await self.db.get_queue(player.guild.id)
        restored = 0
        for item in saved:
            try:
                track = wavelink.Playable(item["data"])
            except Exception:
                continue
            player.queue.put(track)
            restored += 1
        if restored:
            log.info("Restored %s queued tracks for guild %s",
                     restored, player.guild.id)
        return restored

    async def teardown(self, player: wavelink.Player,
                       announce_to: "Optional[discord.abc.Messageable]" = None) -> None:
        """Stop everything and disconnect."""
        guild = player.guild
        self._live.pop(guild.id, None)
        player.queue.clear()
        try:
            await player.stop()
        except Exception:
            pass
        try:
            await player.disconnect()
        except Exception:
            pass
        await self.db.replace_queue(guild.id, [])
        if announce_to is not None:
            try:
                await announce_to.send("Disconnected. Queue cleared.")
            except discord.HTTPException:
                pass

    async def persist_volume(self, guild: "Optional[discord.Guild]", volume: int) -> None:
        if guild is not None:
            await self.db.set_volume(guild.id, volume)

    def announce_channel(self, guild: discord.Guild) -> "Optional[discord.abc.Messageable]":
        channel = self.announce_channels.get(guild.id)
        if channel is not None:
            return channel
        if guild.system_channel and guild.system_channel.permissions_for(
                guild.me).send_messages:
            return guild.system_channel
        return None

    # ================================================================== events
    @commands.Cog.listener()
    async def on_wavelink_node_ready(self, payload: wavelink.NodeReadyEventPayload):
        log.info("Lavalink node ready: %s (session=%s, resumed=%s)",
                 payload.node.identifier, payload.session_id, payload.resumed)
        if payload.resumed:
            # Lavalink restored the players itself (session resuming) - the
            # audio continues seamlessly, nothing to rebuild.
            return
        # The node came back but the session was NOT resumed (e.g. Lavalink
        # was restarted or down longer than the resume window). Wavelink keeps
        # client-side player objects, but the Lavalink-side players are gone:
        # the bot would sit in the voice channel in total silence. Rebuild.
        if self._live and not self._recovering:
            asyncio.create_task(self._recover_players())

    async def _recover_players(self) -> None:
        """Rebuild every player after Lavalink lost its session.

        For each guild that was playing: reconnect to the same voice channel,
        re-apply the stored volume, restore the persisted queue and resume the
        current track at (approximately) the position it was at. If the exact
        track cannot be resumed, the next queued track starts instead.
        """
        log.info("Recovering %s player(s) after Lavalink restart...",
                 len(self._live))
        self._recovering = True
        try:
            await self._recover_players_locked()
        finally:
            self._recovering = False

    async def _recover_players_locked(self) -> None:
        for guild_id, state in list(self._live.items()):
            guild = self.bot.get_guild(guild_id)
            if guild is None:
                self._live.pop(guild_id, None)
                continue
            existing = guild.voice_client
            if isinstance(existing, wavelink.Player) \
                    and existing.current is not None:
                # Another node_ready event already recovered this guild.
                continue
            try:
                channel_id = state.get("voice_channel_id")
                channel = guild.get_channel(channel_id) if channel_id else None

                old = guild.voice_client
                if old is not None:
                    try:
                        await asyncio.wait_for(old.disconnect(force=True),
                                               timeout=10)
                    except Exception:  # noqa: BLE001
                        pass
                    await asyncio.sleep(1)

                if not isinstance(channel,
                                  (discord.VoiceChannel, discord.StageChannel)):
                    self._live.pop(guild_id, None)
                    continue

                player: wavelink.Player = await asyncio.wait_for(
                    channel.connect(cls=wavelink.Player, self_deaf=True,
                                    timeout=20.0),
                    timeout=25.0)
                stored_volume = await self.db.get_volume(guild.id)
                await player.set_volume(
                    stored_volume if stored_volume is not None
                    else self.cfg.DEFAULT_VOLUME)
                await self.restore_queue(player)

                resumed = False
                try:
                    track = wavelink.Playable(state["track_raw"])
                except Exception:  # noqa: BLE001
                    track = None
                if track is not None:
                    elapsed_ms = int((time.time()
                                      - state.get("started_at", time.time()))
                                     * 1000)
                    try:
                        await player.play(track, start=max(0, elapsed_ms))
                        resumed = True
                    except Exception as error:  # noqa: BLE001
                        log.warning("Could not resume the current track in "
                                    "%s: %s", guild.id, error)
                if not resumed:
                    try:
                        next_track = player.queue.get()
                        await player.play(next_track)
                    except wavelink.QueueEmpty:
                        pass

                log.info("Player recovered in guild %s after Lavalink "
                         "restart.", guild.id)
                announce = (self.announce_channels.get(guild.id)
                            or self.announce_channel(guild))
                if announce is not None:
                    try:
                        await announce.send(
                            "\U0001F501 **Reconnected** to the audio engine "
                            "and resumed playback.")
                    except discord.HTTPException:
                        pass
            except Exception as error:  # noqa: BLE001
                log.error("Player recovery failed in guild %s: %s",
                          guild_id, error)

    @commands.Cog.listener()
    async def on_wavelink_track_start(self, payload: wavelink.TrackStartEventPayload):
        player = payload.player
        if player is None or player.guild is None:
            return
        track = payload.track
        log.info("Track started in %s: %s", player.guild.id, track.title)
        self._live[player.guild.id] = {
            "voice_channel_id": player.channel.id if player.channel else None,
            "track_raw": track.raw_data,
            "started_at": time.time(),
        }
        channel = self.announce_channel(player.guild)
        if channel is None:
            return
        try:
            view = NowPlayingView(self.bot)
            await channel.send(embed=build_now_playing_embed(player), view=view)
        except discord.HTTPException as error:
            log.debug("Could not send now-playing embed: %s", error)

    @commands.Cog.listener()
    async def on_wavelink_track_end(self, payload: wavelink.TrackEndEventPayload):
        player = payload.player
        if player is None or player.guild is None:
            return
        reason = payload.reason

        if reason not in ("finished", "loadFailed"):
            # "stopped" / "replaced" / "cancelled": we intentionally started
            # something else, the queue must NOT advance.
            return

        channel = self.announce_channel(player.guild)

        if reason == "loadFailed":
            # YouTube often rejects datacenter IPs at playback time ("This
            # video requires login"). Try a SoundCloud replacement for the
            # same song before giving up and advancing the queue.
            failed = payload.track
            replacement = await self._soundcloud_replacement(failed)
            if replacement is not None:
                try:
                    await player.play(replacement)
                    log.info("Rescued playback via SoundCloud: %s",
                             getattr(replacement, "title", "?"))
                    if channel is not None:
                        try:
                            await channel.send(
                                f"YouTube failed for **{failed.title}** - "
                                "playing it from SoundCloud instead.")
                        except discord.HTTPException:
                            pass
                    await self.persist_queue(player)
                    return
                except Exception as error:
                    log.warning("SoundCloud replacement play failed: %s", error)
            if channel is not None:
                try:
                    await channel.send(
                        f"Track failed to load: **{payload.track.title}** - skipping.")
                except discord.HTTPException:
                    pass

        try:
            next_track = player.queue.get()
        except wavelink.QueueEmpty:
            await self.persist_queue(player)
            channel = self.announce_channel(player.guild)
            if channel is not None and reason == "finished":
                try:
                    await channel.send("Queue finished. Add more music with `/play`!")
                except discord.HTTPException:
                    pass
            return

        try:
            await player.play(next_track)
        except Exception as error:
            log.error("Failed to start next track: %s", error)
        await self.persist_queue(player)

    async def _soundcloud_replacement(self, failed):
        """Find a SoundCloud stand-in for a track that failed to play.

        Each song is rescued at most once (tracked in self._rescued) so a
        failing SoundCloud track cannot create an endless rescue loop."""
        if failed is None:
            return None
        title = getattr(failed, "title", "")
        author = getattr(failed, "author", "")
        query = " ".join(x for x in (title, author) if x)
        if not query:
            return None
        key = query.lower()
        if key in self._rescued:
            return None
        self._rescued.add(key)
        try:
            results = await wavelink.Playable.search(
                query, source=wavelink.TrackSource.SoundCloud)
        except Exception as error:
            log.warning("SoundCloud replacement search failed: %s", error)
            return None
        for candidate in (results or []):
            if getattr(candidate, "identifier", "") != getattr(failed, "identifier", ""):
                return candidate
        return None

    @commands.Cog.listener()
    async def on_wavelink_track_exception(self, payload):
        player = getattr(payload, "player", None)
        track = getattr(payload, "track", None)
        log.warning("Track exception: %s", getattr(track, "title", "unknown"))

    @commands.Cog.listener()
    async def on_wavelink_track_stuck(self, payload):
        player = getattr(payload, "player", None)
        if player is not None:
            try:
                await player.skip(force=True)
            except Exception:
                pass

    @commands.Cog.listener()
    async def on_wavelink_inactive_player(self, player: wavelink.Player):
        """Fires after AUTO_DISCONNECT_SECONDS of inactivity (wavelink built-in)."""
        if self.cfg.AUTO_DISCONNECT_SECONDS <= 0:
            return
        log.info("Player inactive in guild %s - disconnecting.", player.guild.id)
        channel = self.announce_channel(player.guild)
        await self.teardown(player)
        if channel is not None:
            try:
                await channel.send(
                    "Left the voice channel due to inactivity.")
            except discord.HTTPException:
                pass

    # ================================================================== play
    @commands.hybrid_command(name="play", aliases=["p", "add"],
                             description="Play a song or playlist from a URL or search term.")
    @app_commands.describe(query="Song name or URL (YouTube / Spotify / SoundCloud / Deezer)")
    async def play(self, ctx: commands.Context, *, query: str):
        # Ephemeral defer first (slash needs a fast ack); the final message is
        # still public because it is sent as a followup.
        await ctx.defer(ephemeral=True)
        self.announce_channels[ctx.guild.id] = ctx.channel  # type: ignore[union-attr]

        player = await self.ensure_voice(ctx)
        if player is None:
            return

        # Restore a queue persisted before a restart, so it is not lost.
        await self.restore_queue(player)

        try:
            tracks, playlist_name = await self.fetch_tracks(query)
        except wavelink.LavalinkLoadException as error:
            log.warning("Load failed for %r: %s", query, error)
            await ctx.send("Could not load that track/URL. Try a different link or name.")
            return

        if not tracks:
            await ctx.send(f"No results for: **{query}**")
            return

        for track in tracks:
            player.queue.put(track)

        total = len(tracks)
        first = tracks[0]

        if player.current is None:
            try:
                next_track = player.queue.get()
                await player.play(next_track)
            except wavelink.QueueEmpty:
                await ctx.send("Something went wrong starting playback. Try again.")
                return

        if playlist_name:
            message = (f"Loaded playlist **{playlist_name}** with "
                       f"**{total}** tracks from **{first.source}**.")
        elif total > 1:
            message = (f"Queued **{total}** tracks. Starting with "
                       f"**{first.title}**.")
        elif player.current is first:
            message = f"Playing **{first.title}**."
        else:
            message = (f"Queued **{first.title}** at position "
                       f"**{player.queue.count}** in the queue.")
        await ctx.send(message)
        await self.persist_queue(player)

    @commands.hybrid_command(name="search", description="Search and pick a track with buttons.")
    @app_commands.describe(query="What to search for")
    async def search(self, ctx: commands.Context, *, query: str):
        await ctx.defer(ephemeral=True)
        self.announce_channels[ctx.guild.id] = ctx.channel  # type: ignore[union-attr]
        try:
            tracks, _ = await self.fetch_tracks(query)
        except wavelink.LavalinkLoadException:
            await ctx.send("Could not search for that. Try again.")
            return
        if not tracks:
            await ctx.send(f"No results for: **{query}**")
            return

        lines = []
        for index, track in enumerate(tracks[:5]):
            lines.append(f"**{index + 1}.** [{track.title}]({track.uri}) "
                         f"`{format_time(track.length)}`")
        embed = discord.Embed(title=f"Results for: {query}",
                              description="\n".join(lines), color=0x5865F2)
        embed.set_footer(text="Pick a track with the buttons (60 seconds).")

        async def on_pick(interaction: discord.Interaction,
                          track: wavelink.Playable):
            player = await self.ensure_voice_itx(interaction)
            if player is None:
                return
            player.queue.put(track)
            if player.current is None:
                next_track = player.queue.get()
                await player.play(next_track)
            await self.persist_queue(player)
            await interaction.followup.send(
                f"Queued **{track.title}**.", ephemeral=False)

        view = SearchView(ctx.author, on_pick)
        view.build_buttons(tracks)
        message = await ctx.send(embed=embed, view=view)
        view.message = message

    # ================================================================== control
    @commands.hybrid_command(name="pause", description="Pause the current track.")
    async def pause(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.current is None:
            await ctx.send("Nothing is playing right now.", ephemeral=True)
            return
        if player.paused:
            await ctx.send("Already paused.", ephemeral=True)
            return
        await player.pause(True)
        await ctx.send("Paused.")

    @commands.hybrid_command(name="resume", aliases=["unpause"],
                             description="Resume the paused track.")
    async def resume(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.current is None:
            await ctx.send("Nothing is paused right now.", ephemeral=True)
            return
        if not player.paused:
            await ctx.send("Music is already playing.", ephemeral=True)
            return
        await player.pause(False)
        await ctx.send("Resumed.")

    @commands.hybrid_command(name="skip", aliases=["s", "next"],
                             description="Skip the current track.")
    async def skip(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.current is None:
            await ctx.send("Nothing to skip.", ephemeral=True)
            return
        await ctx.defer()

        was_looping = player.queue.mode == wavelink.QueueMode.loop
        if was_looping:
            player.queue.mode = wavelink.QueueMode.normal
        try:
            next_track = player.queue.get()
        except wavelink.QueueEmpty:
            next_track = None
        finally:
            if was_looping:
                player.queue.mode = wavelink.QueueMode.loop

        if next_track is None:
            await player.stop()
            await ctx.send("Queue is empty. Playback stopped.")
            await self.persist_queue(player)
            return

        await player.play(next_track)
        await ctx.send(f"Skipped. Now playing **{next_track.title}**.")
        await self.persist_queue(player)

    @commands.hybrid_command(name="stop", aliases=["leave", "dc", "disconnect"],
                             description="Stop playback and leave the voice channel.")
    async def stop(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player):
            await ctx.send("I am not connected to a voice channel.", ephemeral=True)
            return
        await ctx.defer()
        await self.teardown(player, announce_to=None)
        await ctx.send("Stopped and disconnected.")

    @commands.hybrid_command(name="join", aliases=["summon"],
                             description="Join your voice channel.")
    async def join(self, ctx: commands.Context):
        player = await self.ensure_voice(ctx)
        if player is not None:
            await ctx.send(f"Joined **{player.channel.name}**.")

    @commands.hybrid_command(name="volume", aliases=["vol"],
                             description="Set the playback volume (0-max).")
    @app_commands.describe(volume="New volume (0-150, default 60)")
    async def volume(self, ctx: commands.Context, volume: commands.Range[int, 0, 200]):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player):
            await ctx.send("I am not connected to a voice channel.", ephemeral=True)
            return
        volume = min(volume, self.cfg.MAX_VOLUME)
        await player.set_volume(volume)
        await self.persist_volume(ctx.guild, volume)
        await ctx.send(f"Volume set to **{volume}%**.")

    @commands.hybrid_command(name="loop", description="Loop the current track or the whole queue.")
    @app_commands.describe(mode="off = no loop, track = repeat current, queue = loop all")
    async def loop(self, ctx: commands.Context, mode: str = "track"):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player):
            await ctx.send("I am not connected to a voice channel.", ephemeral=True)
            return
        mode = mode.lower()
        modes = {"off": wavelink.QueueMode.normal,
                 "none": wavelink.QueueMode.normal,
                 "track": wavelink.QueueMode.loop,
                 "one": wavelink.QueueMode.loop,
                 "queue": wavelink.QueueMode.loop_all,
                 "all": wavelink.QueueMode.loop_all}
        if mode not in modes:
            await ctx.send("Usage: `loop off|track|queue`", ephemeral=True)
            return
        player.queue.mode = modes[mode]
        names = {wavelink.QueueMode.normal: "off",
                 wavelink.QueueMode.loop: "current track",
                 wavelink.QueueMode.loop_all: "whole queue"}
        await ctx.send(f"Looping is now **{names[player.queue.mode]}**.")

    @commands.hybrid_command(name="shuffle", description="Shuffle the queue.")
    async def shuffle(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.queue.count < 2:
            await ctx.send("Need at least 2 tracks in the queue to shuffle.",
                           ephemeral=True)
            return
        player.queue.shuffle()
        await self.persist_queue(player)
        await ctx.send(f"Shuffled **{player.queue.count}** tracks.")

    @commands.hybrid_command(name="clear", description="Clear the queue (keeps current track).")
    async def clear(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.queue.count == 0:
            await ctx.send("The queue is already empty.", ephemeral=True)
            return
        removed = player.queue.count
        player.queue.clear()
        await self.persist_queue(player)
        await ctx.send(f"Removed **{removed}** tracks from the queue.")

    @commands.hybrid_command(name="remove", description="Remove a track from the queue by position.")
    @app_commands.describe(position="Queue position (see the queue command)")
    async def remove(self, ctx: commands.Context, position: commands.Range[int, 1, 500]):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.queue.count == 0:
            await ctx.send("The queue is empty.", ephemeral=True)
            return
        index = position - 1
        if index >= player.queue.count:
            await ctx.send(f"There is no position **{position}** "
                           f"(queue has {player.queue.count} tracks).", ephemeral=True)
            return
        track = player.queue[index]
        del player.queue[index]
        await self.persist_queue(player)
        await ctx.send(f"Removed **{track.title}** from the queue.")

    @commands.hybrid_command(name="skipto", aliases=["jumpto"],
                             description="Skip to a specific position in the queue.")
    @app_commands.describe(position="Queue position to jump to")
    async def skipto(self, ctx: commands.Context, position: commands.Range[int, 1, 500]):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.queue.count == 0:
            await ctx.send("The queue is empty.", ephemeral=True)
            return
        index = position - 1
        if index >= player.queue.count:
            await ctx.send(f"There is no position **{position}** "
                           f"(queue has {player.queue.count} tracks).", ephemeral=True)
            return
        await ctx.defer()
        for _ in range(index):
            try:
                player.queue.get()
            except wavelink.QueueEmpty:
                break
        target = player.queue.get()
        await player.play(target)
        await self.persist_queue(player)
        await ctx.send(f"Jumped to **{target.title}** (position {position}).")

    @commands.hybrid_command(name="seek",
                             description="Seek within the current track (seconds or m:ss).")
    @app_commands.describe(position="Time like 90 or 1:30")
    async def seek(self, ctx: commands.Context, *, position: str):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.current is None:
            await ctx.send("Nothing is playing right now.", ephemeral=True)
            return
        if not player.current.is_seekable:
            await ctx.send("This track cannot be seeked (live stream).", ephemeral=True)
            return
        seconds = parse_time(position)
        if seconds is None:
            await ctx.send("Could not parse that time. Examples: `45`, `1:30`, `2:05:10`.",
                           ephemeral=True)
            return
        seconds = min(seconds, int(player.current.length / 1000))
        await player.seek(seconds * 1000)
        await ctx.send(f"Seeked to **{format_time(seconds * 1000)}**.")

    @commands.hybrid_command(name="replay", description="Restart the current track.")
    async def replay(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.current is None:
            await ctx.send("Nothing is playing right now.", ephemeral=True)
            return
        await player.seek(0)
        await ctx.send("Restarted the current track.")

    # ================================================================== info
    @commands.hybrid_command(name="queue", aliases=["q"],
                             description="Show the current queue.")
    async def queue(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player):
            await ctx.send("I am not connected to a voice channel.", ephemeral=True)
            return

        embed = discord.Embed(title="Queue", color=0x5865F2)
        if player.current is not None:
            embed.add_field(
                name="Now playing",
                value=f"[{player.current.title}]({player.current.uri}) "
                      f"`{format_time(player.position)} / {format_time(player.current.length)}`",
                inline=False,
            )
        queued = list(player.queue)
        if not queued:
            embed.description = "The queue is empty. Add music with `/play`!"
        else:
            lines = []
            for index, track in enumerate(queued[:10], start=1):
                lines.append(f"`{index}.` [{track.title}]({track.uri}) "
                             f"`{format_time(track.length)}`")
            embed.description = "\n".join(lines)
            if len(queued) > 10:
                embed.set_footer(text=f"...and {len(queued) - 10} more tracks. "
                                      f"Total length: {format_time(sum(t.length for t in queued))}")
        await ctx.send(embed=embed)

    @commands.hybrid_command(name="nowplaying", aliases=["np"],
                             description="Show the track that is currently playing.")
    async def nowplaying(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.current is None:
            await ctx.send("Nothing is playing right now.", ephemeral=True)
            return
        await ctx.send(embed=build_now_playing_embed(player))

    @commands.hybrid_command(name="history",
                             description="Show recently played tracks.")
    async def history(self, ctx: commands.Context):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player) or player.history.count == 0:
            await ctx.send("No tracks have been played yet.", ephemeral=True)
            return
        items = list(player.history)[-5:][::-1]
        lines = [f"[{track.title}]({track.uri})" for track in items]
        embed = discord.Embed(title="Recently played",
                              description="\n".join(lines), color=0x5865F2)
        await ctx.send(embed=embed)

    # ================================================================== playlists
    @commands.hybrid_group(name="playlist", aliases=["pl"],
                           description="Manage saved playlists.",
                           invoke_without_command=True)
    async def playlist(self, ctx: commands.Context):
        rows = await self.db.playlist_list(ctx.guild.id)  # type: ignore[union-attr]
        if not rows:
            await ctx.send("No saved playlists yet. Create one with "
                           "`/playlist create <name>`.")
            return
        lines = [f"**{name}** - {count} tracks" for _, name, count in rows]
        embed = discord.Embed(title="Saved playlists",
                              description="\n".join(lines), color=0x5865F2)
        await ctx.send(embed=embed)

    @playlist.command(name="create", description="Create a new empty playlist.")
    @app_commands.describe(name="Playlist name")
    async def playlist_create(self, ctx: commands.Context, *, name: str):
        name = name.strip()[:100]
        created = await self.db.playlist_create(ctx.guild.id, name,  # type: ignore[union-attr]
                                                ctx.author.id)  # type: ignore[union-attr]
        if not created:
            await ctx.send(f"A playlist named **{name}** already exists.", ephemeral=True)
            return
        await ctx.send(f"Playlist **{name}** created. Add songs with "
                       f"`/playlist add {name}` while music is playing.")

    @playlist.command(name="delete", description="Delete a saved playlist.")
    @app_commands.describe(name="Playlist name")
    async def playlist_delete(self, ctx: commands.Context, *, name: str):
        deleted = await self.db.playlist_delete(ctx.guild.id, name.strip())  # type: ignore[union-attr]
        if not deleted:
            await ctx.send(f"No playlist named **{name}**.", ephemeral=True)
            return
        await ctx.send(f"Playlist **{name}** deleted.")

    @playlist.command(name="add", description="Save the current track (or whole queue) to a playlist.")
    @app_commands.describe(name="Playlist name", scope="track = current song only, queue = whole queue")
    async def playlist_add(self, ctx: commands.Context, *, name: str,
                           scope: str = "track"):
        player = ctx.guild.voice_client if ctx.guild else None
        if not isinstance(player, wavelink.Player):
            await ctx.send("Nothing is playing right now.", ephemeral=True)
            return
        pl = await self.db.playlist_get(ctx.guild.id, name.strip())  # type: ignore[union-attr]
        if pl is None:
            await ctx.send(f"No playlist named **{name}**. Create it first with "
                           f"`/playlist create {name}`.", ephemeral=True)
            return

        requester = ctx.author.id  # type: ignore[union-attr]
        if scope.lower() == "queue":
            items = []
            if player.current is not None:
                items.append(self.track_snapshot(player.current, requester))
            items.extend({"data": t.raw_data, "requester": requester}
                         for t in list(player.queue))
            tracks = items
        else:
            if player.current is None:
                await ctx.send("Nothing is playing right now.", ephemeral=True)
                return
            tracks = [self.track_snapshot(player.current, requester)]

        added = await self.db.playlist_add_tracks(pl["id"], tracks)
        await ctx.send(f"Added **{added}** tracks to playlist **{name}**.")

    @playlist.command(name="load", description="Load a playlist into the queue.")
    @app_commands.describe(name="Playlist name")
    async def playlist_load(self, ctx: commands.Context, *, name: str):
        player = await self.ensure_voice(ctx)
        if player is None:
            return
        pl = await self.db.playlist_get(ctx.guild.id, name.strip())  # type: ignore[union-attr]
        if pl is None:
            await ctx.send(f"No playlist named **{name}**.", ephemeral=True)
            return
        items = await self.db.playlist_get_tracks(pl["id"])
        tracks = []
        for item in items:
            try:
                tracks.append(wavelink.Playable(item["data"]))
            except Exception:
                continue
        if not tracks:
            await ctx.send(f"Playlist **{name}** is empty or its tracks could "
                           "not be restored.", ephemeral=True)
            return
        for track in tracks:
            player.queue.put(track)
        if player.current is None:
            next_track = player.queue.get()
            await player.play(next_track)
        await self.persist_queue(player)
        await ctx.send(f"Loaded **{len(tracks)}** tracks from playlist **{name}**.")

    @playlist.command(name="info", description="Show the tracks inside a playlist.")
    @app_commands.describe(name="Playlist name")
    async def playlist_info(self, ctx: commands.Context, *, name: str):
        pl = await self.db.playlist_get(ctx.guild.id, name.strip())  # type: ignore[union-attr]
        if pl is None:
            await ctx.send(f"No playlist named **{name}**.", ephemeral=True)
            return
        items = await self.db.playlist_get_tracks(pl["id"])
        if not items:
            await ctx.send(f"Playlist **{name}** is empty.")
            return
        lines = []
        for index, item in enumerate(items[:10], start=1):
            info = item["data"].get("info", {})
            title = info.get("title", "unknown")
            uri = info.get("uri")
            if uri:
                lines.append(f"`{index}.` [{title}]({uri})")
            else:
                lines.append(f"`{index}.` {title}")
        embed = discord.Embed(title=f"Playlist: {name}",
                              description="\n".join(lines), color=0x5865F2)
        if len(items) > 10:
            embed.set_footer(text=f"...and {len(items) - 10} more tracks.")
        await ctx.send(embed=embed)

    # ================================================================== help
    @commands.hybrid_command(name="help", description="Show all commands.")
    async def help_command(self, ctx: commands.Context):
        prefix = self.cfg.PREFIX
        embed = discord.Embed(
            title="Music Bot - Commands",
            description=("Every command works as a **slash command** (`/play`) "
                         f"and with the **prefix** (`{prefix}play`)."),
            color=0x5865F2,
        )
        embed.add_field(
            name="Playback",
            value=("`play (p)` - play a song/URL\n"
                   "`search` - search with buttons\n"
                   "`pause` / `resume` - pause & resume\n"
                   "`skip (s)` - skip track\n"
                   "`stop` - stop & disconnect\n"
                   "`join` - join your channel\n"
                   "`replay` - restart track"),
            inline=False,
        )
        embed.add_field(
            name="Queue",
            value=("`queue (q)` - show queue\n"
                   "`nowplaying (np)` - current track\n"
                   "`loop off|track|queue`\n"
                   "`shuffle` / `clear`\n"
                   "`remove <pos>` / `skipto <pos>`\n"
                   "`seek <time>` / `history`"),
            inline=False,
        )
        embed.add_field(
            name="Other",
            value=("`volume <0-150>`\n"
                   "`playlist create|add|load|list|info|delete`\n"
                   "`help` - this message"),
            inline=False,
        )
        embed.set_footer(text=f"Volume is saved per server. Auto-leave after "
                              f"{self.cfg.AUTO_DISCONNECT_SECONDS}s of inactivity.")
        await ctx.send(embed=embed)


def parse_time(text: str) -> "Optional[int]":
    """Parse '90', '1:30' or '1:02:05' into seconds."""
    text = text.strip()
    if not re.fullmatch(r"[\d:]+", text):
        return None
    parts = [int(p) for p in text.split(":")]
    if len(parts) > 3 or any(p < 0 for p in parts):
        return None
    seconds = 0
    for part in parts:
        seconds = seconds * 60 + part
    return seconds


async def setup(bot):
    await bot.add_cog(MusicCog(bot))
ZEOF_MUSIC_PY
COPY <<'ZEOF_VIEWS_PY' /app/views.py
"""
Interactive UI components:

  - NowPlayingView : persistent control buttons attached to the "Now playing" embed
  - SearchView     : pick one of the top-5 search results with buttons
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Callable, Optional

import discord
import wavelink

if TYPE_CHECKING:
    from main import MusicBot


def build_now_playing_embed(player: wavelink.Player) -> discord.Embed:
    """Build (or refresh) the Now Playing embed from the player state."""
    track: "Optional[wavelink.Playable]" = player.current
    if track is None:
        embed = discord.Embed(
            title="Nothing playing",
            description="The queue is empty. Use `/play` or `?play` to add music!",
            color=0xED4245,
        )
        return embed

    mode = player.queue.mode
    loop_text = {wavelink.QueueMode.normal: "Off",
                 wavelink.QueueMode.loop: "Track",
                 wavelink.QueueMode.loop_all: "Queue"}[mode]

    embed = discord.Embed(
        title="Now playing",
        description=f"**[{track.title}]({track.uri})**",
        color=0x5865F2,
    )
    if track.artwork:
        embed.set_thumbnail(url=track.artwork)
    embed.add_field(name="Author", value=track.author or "Unknown", inline=True)
    embed.add_field(name="Source", value=str(track.source).split(".")[-1].capitalize(), inline=True)
    remaining = max(track.length - player.position, 0)
    embed.add_field(
        name="Time",
        value=f"{format_time(player.position)} / {format_time(track.length)} "
              f"({format_time(remaining)} left)",
        inline=False,
    )
    embed.add_field(name="Volume", value=f"{player.volume}%", inline=True)
    embed.add_field(name="Loop", value=loop_text, inline=True)
    embed.add_field(name="In queue", value=str(player.queue.count), inline=True)
    if player.paused:
        embed.set_footer(text="Paused")
    return embed


def format_time(ms: int) -> str:
    seconds = int(ms / 1000)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    if hours:
        return f"{hours}:{minutes:02}:{seconds:02}"
    return f"{minutes}:{seconds:02}"


def same_voice(itx: discord.Interaction, player: wavelink.Player) -> bool:
    """The user must share a voice channel with the bot to use the buttons."""
    if player.channel is None or itx.user is None:
        return False
    voice = itx.user.voice
    if voice is None or voice.channel is None:
        return False
    return voice.channel.id == player.channel.id


class NowPlayingView(discord.ui.View):
    """Persistent playback controls attached to the Now Playing message."""

    def __init__(self, bot: "MusicBot"):
        super().__init__(timeout=None)
        self.bot = bot

    async def _get_player(self, itx: discord.Interaction) -> "Optional[wavelink.Player]":
        if itx.guild is None or itx.guild.voice_client is None:
            await itx.response.send_message(
                "I am not connected to a voice channel right now.", ephemeral=True)
            return None
        player = itx.guild.voice_client
        if not isinstance(player, wavelink.Player):
            await itx.response.send_message("No active player.", ephemeral=True)
            return None
        if not same_voice(itx, player):
            await itx.response.send_message(
                "Join my voice channel first to use the controls.", ephemeral=True)
            return None
        return player

    # ---- play / pause -------------------------------------------------
    @discord.ui.button(emoji="\u23F8", label="Pause",
                       style=discord.ButtonStyle.primary, custom_id="np:playpause")
    async def playpause(self, itx: discord.Interaction,
                        button: discord.ui.Button):
        player = await self._get_player(itx)
        if player is None:
            return
        if player.current is None:
            await itx.response.send_message("Nothing is playing.", ephemeral=True)
            return
        await player.pause(not player.paused)
        button.emoji = "\u25B6" if player.paused else "\u23F8"
        button.label = "Resume" if player.paused else "Pause"
        await itx.response.edit_message(embed=build_now_playing_embed(player), view=self)

    # ---- skip ---------------------------------------------------------
    @discord.ui.button(emoji="\u23ED", label="Skip",
                       style=discord.ButtonStyle.primary, custom_id="np:skip")
    async def skip(self, itx: discord.Interaction, button: discord.ui.Button):
        player = await self._get_player(itx)
        if player is None:
            return
        if player.current is None:
            await itx.response.send_message("Nothing to skip.", ephemeral=True)
            return
        await itx.response.defer()
        await player.skip(force=True)

    # ---- stop ---------------------------------------------------------
    @discord.ui.button(emoji="\u23F9", label="Stop",
                       style=discord.ButtonStyle.danger, custom_id="np:stop")
    async def stop(self, itx: discord.Interaction, button: discord.ui.Button):
        player = await self._get_player(itx)
        if player is None:
            return
        await itx.response.defer()
        await self.bot.music.teardown(player, announce_to=itx.channel)

    # ---- loop ---------------------------------------------------------
    @discord.ui.button(emoji="\U0001F501", label="Loop: Off",
                       style=discord.ButtonStyle.secondary, custom_id="np:loop")
    async def loop(self, itx: discord.Interaction, button: discord.ui.Button):
        player = await self._get_player(itx)
        if player is None:
            return
        cycle = {wavelink.QueueMode.normal: wavelink.QueueMode.loop,
                 wavelink.QueueMode.loop: wavelink.QueueMode.loop_all,
                 wavelink.QueueMode.loop_all: wavelink.QueueMode.normal}
        player.queue.mode = cycle[player.queue.mode]
        labels = {wavelink.QueueMode.normal: "Loop: Off",
                  wavelink.QueueMode.loop: "Loop: Track",
                  wavelink.QueueMode.loop_all: "Loop: Queue"}
        button.label = labels[player.queue.mode]
        await itx.response.edit_message(embed=build_now_playing_embed(player), view=self)

    # ---- shuffle ------------------------------------------------------
    @discord.ui.button(emoji="\U0001F500", label="Shuffle",
                       style=discord.ButtonStyle.secondary, custom_id="np:shuffle")
    async def shuffle(self, itx: discord.Interaction, button: discord.ui.Button):
        player = await self._get_player(itx)
        if player is None:
            return
        if player.queue.count < 2:
            await itx.response.send_message(
                "Need at least 2 tracks in the queue to shuffle.", ephemeral=True)
            return
        player.queue.shuffle()
        await itx.response.edit_message(embed=build_now_playing_embed(player), view=self)

    # ---- volume -------------------------------------------------------
    @discord.ui.button(emoji="\U0001F509", label="-10",
                       style=discord.ButtonStyle.secondary, custom_id="np:volupdn")
    async def volume_down(self, itx: discord.Interaction, button: discord.ui.Button):
        player = await self._get_player(itx)
        if player is None:
            return
        new_volume = max(0, player.volume - 10)
        await player.set_volume(new_volume)
        await self.bot.music.persist_volume(itx.guild, new_volume)
        await itx.response.edit_message(embed=build_now_playing_embed(player), view=self)

    @discord.ui.button(emoji="\U0001F50A", label="+10",
                       style=discord.ButtonStyle.secondary, custom_id="np:volup")
    async def volume_up(self, itx: discord.Interaction, button: discord.ui.Button):
        player = await self._get_player(itx)
        if player is None:
            return
        new_volume = min(self.bot.cfg.MAX_VOLUME, player.volume + 10)
        await player.set_volume(new_volume)
        await self.bot.music.persist_volume(itx.guild, new_volume)
        await itx.response.edit_message(embed=build_now_playing_embed(player), view=self)


class SearchView(discord.ui.View):
    """Buttons to pick one of up to 5 search results."""

    def __init__(self, requester: discord.abc.User,
                 on_pick: "Callable[[discord.Interaction, wavelink.Playable], None]"):
        super().__init__(timeout=120)
        self.requester = requester
        self.on_pick = on_pick
        self.message: "Optional[discord.Message]" = None
        self.tracks: "list[wavelink.Playable]" = []

    async def interaction_check(self, itx: discord.Interaction) -> bool:
        if itx.user.id != self.requester.id:
            await itx.response.send_message(
                "Only the person who ran the search can choose.", ephemeral=True)
            return False
        return True

    async def on_timeout(self) -> None:
        if self.message is not None:
            try:
                await self.message.edit(content="Search timed out.", view=None)
            except discord.HTTPException:
                pass

    def build_buttons(self, tracks: "list[wavelink.Playable]") -> None:
        self.tracks = list(tracks[:5])
        for index, track in enumerate(self.tracks):
            button = discord.ui.Button(
                label=str(index + 1),
                style=discord.ButtonStyle.primary,
                custom_id=f"search:{index}",
            )
            button.callback = self._make_callback(index)
            self.add_item(button)
        cancel = discord.ui.Button(label="Cancel",
                                   style=discord.ButtonStyle.danger,
                                   custom_id="search:cancel")
        cancel.callback = self._cancel_callback
        self.add_item(cancel)

    def _make_callback(self, index: int):
        async def callback(itx: discord.Interaction):
            await itx.response.defer()
            track = self.tracks[index]
            for child in self.children:
                child.disabled = True  # type: ignore[attr-defined]
            try:
                await self.message.edit(view=self)
            except discord.HTTPException:
                pass
            await self.on_pick(itx, track)
        return callback

    def _cancel_callback(self):
        async def callback(itx: discord.Interaction):
            await itx.response.edit_message(content="Search cancelled.", view=None)
        return callback
ZEOF_VIEWS_PY
COPY <<'ZEOF_AUTO_TEST_PY' /app/Scripts/auto_test.py
"""
Automated end-to-end test for the music bot.

Runs when AUTOTEST=1 is set. Sequence:
  1. Find a guild the bot is in and join a voice channel.
  2. Search a track on SoundCloud and play it.
  3. Verify REAL playback: track start event + audio position advancing
     + voice UDP ping (this proves audio is being streamed to Discord).
  4. Test pause / resume / seek / volume / queue / skip.
  5. Try a YouTube search too (reported separately, datacenter IPs are
     sometimes rate-limited by YouTube - SoundCloud result is decisive).
  6. Optional (RECOVERY_TEST=1): kill-and-restart Lavalink mid-playback and
     verify the bot automatically rebuilds the player and keeps streaming
     - this simulates the "Lavalink server died" scenario end to end.
  7. Disconnect, write e2e_result.json and exit(0/1).

Run standalone:  AUTOTEST=1 DISCORD_TOKEN=... python main.py
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from typing import Optional

import discord
import wavelink

log = logging.getLogger("musicbot.autotest")

RESULT_PATH = os.environ.get("E2E_RESULT_PATH", "e2e_result.json")


class Step:
    def __init__(self, name: str):
        self.name = name
        self.ok = False
        self.detail = ""


class AutoTest:
    def __init__(self, bot):
        self.bot = bot
        self.steps: "list[Step]" = []
        self.player: "Optional[wavelink.Player]" = None
        self.guild: "Optional[discord.Guild]" = None

    def step(self, name: str, ok: bool, detail: str = "") -> None:
        self.steps.append(Step(name))
        self.steps[-1].ok = ok
        self.steps[-1].detail = detail
        status = "OK " if ok else "FAIL"
        log.info("E2E: [%s] %s %s", status, name, ("- " + detail) if detail else "")

    # ------------------------------------------------------------- helpers
    async def wait_for_track(self, timeout: float = 20.0) -> "Optional[wavelink.Playable]":
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            player = self.player
            if player is not None and player.current is not None:
                return player.current
            await asyncio.sleep(0.5)
        return None

    async def wait_for_position(self, minimum_ms: int, timeout: float = 45.0) -> int:
        """Wait until the player reports a playback position >= minimum_ms."""
        deadline = time.monotonic() + timeout
        max_seen = 0
        while time.monotonic() < deadline:
            player = self.player
            if player is not None:
                position = player.position
                max_seen = max(max_seen, position)
                if position >= minimum_ms:
                    return position
            await asyncio.sleep(1.0)
        return max_seen

    async def wait_for_current_change(self, old_identifier: str,
                                      timeout: float = 25.0) -> "Optional[wavelink.Playable]":
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            player = self.player
            if player is not None and player.current is not None \
                    and player.current.identifier != old_identifier:
                return player.current
            await asyncio.sleep(0.5)
        return None

    # ---------------------------------------------------------------- main
    async def run(self) -> bool:
        log.info("E2E: starting end-to-end test")

        await asyncio.sleep(3)  # let caches/voice states settle

        # ---- Step 1: guild ------------------------------------------
        guild = self._pick_guild()
        if guild is None:
            client_id = str(getattr(self.bot.user, "id", ""))
            self.step("guild_available", False, "bot is not in any server")
            log.info("E2E: invite the bot with this link, then re-run the test: "
                     "https://discord.com/oauth2/authorize?client_id=%s&scope=bot"
                     "%%20applications.commands&permissions=20007936", client_id)
            return False
        self.step("guild_available", True, f"{guild.name} ({guild.id})")
        self.guild = guild

        # ---- Step 2: voice connection -------------------------------
        channel = self._pick_voice_channel(guild)
        if channel is None:
            self.step("voice_connect", False, "no accessible voice channel")
            return False
        try:
            self.player = await channel.connect(cls=wavelink.Player,
                                                self_deaf=True, timeout=20.0)
        except Exception as error:
            self.step("voice_connect", False, repr(error))
            return False
        self.step("voice_connect", True,
                  f"joined '{channel.name}' (websocket+UDP handshake done)")

        try:
            ok = await self._playback_tests(guild)
        finally:
            await self._cleanup()

        return ok

    # ------------------------------------------------------- playback tests
    async def _playback_tests(self, guild: discord.Guild) -> bool:
        all_ok = True

        # ---- Step 3: search & play (SoundCloud = datacenter-friendly) --
        try:
            results = await wavelink.Playable.search(
                "Never Gonna Give You Up",
                source=wavelink.TrackSource.SoundCloud)
            tracks = list(results or [])
        except Exception as error:
            self.step("search_soundcloud", False, repr(error))
            return False
        self.step("search_soundcloud", bool(tracks),
                  f"{len(tracks)} results" if tracks else "no results")
        if not tracks:
            return False

        track = tracks[0]
        self.player.queue.put(track)
        await self.player.play(self.player.queue.get())

        started = await self.wait_for_track()
        self.step("track_start_event", started is not None,
                  f"now playing: {started.title} [{started.source}]"
                  if started else "no track within 20s")
        if started is None:
            return False
        all_ok &= started is not None

        # ---- Step 4: REAL streaming proof (position advances + ping) ---
        position = await self.wait_for_position(minimum_ms=8000, timeout=40.0)
        ping = self.player.ping
        streaming = position >= 8000
        self.step("audio_streaming", streaming,
                  f"position reached {position}ms (>=8000ms required), "
                  f"voice UDP ping={ping}ms")
        all_ok &= streaming

        # ---- Step 5: pause / resume ------------------------------------
        await self.player.pause(True)
        await asyncio.sleep(1.5)
        paused_ok = self.player.paused
        pos_paused = self.player.position
        await asyncio.sleep(2.0)
        frozen = abs(self.player.position - pos_paused) < 1500
        await self.player.pause(False)
        await asyncio.sleep(1.0)
        resumed_ok = not self.player.paused
        self.step("pause_resume", paused_ok and frozen and resumed_ok,
                  f"paused={paused_ok}, position frozen={frozen}, resumed={resumed_ok}")
        all_ok &= paused_ok and frozen and resumed_ok

        # ---- Step 6: seek -----------------------------------------------
        if self.player.current.is_seekable:
            await self.player.seek(15000)
            await asyncio.sleep(2.5)
            position = self.player.position
            seek_ok = 11000 <= position <= 25000
            self.step("seek", seek_ok, f"position after seek(15s) = {position}ms")
        else:
            self.step("seek", True, "track is a live stream - skipped")
        all_ok &= self.steps[-1].ok

        # ---- Step 7: volume ----------------------------------------------
        await self.player.set_volume(80)
        await asyncio.sleep(0.5)
        volume_ok = self.player.volume == 80
        self.step("volume", volume_ok, f"player.volume={self.player.volume}")
        all_ok &= volume_ok

        # ---- Step 8: queue + skip ------------------------------------------
        try:
            results2 = await wavelink.Playable.search(
                "Never Gonna Give You Up remix",
                source=wavelink.TrackSource.SoundCloud)
            tracks2 = list(results2 or [])
        except Exception:
            tracks2 = []
        if tracks2:
            second = tracks2[0]
            self.player.queue.put(second)
            old_id = self.player.current.identifier
            next_track = self.player.queue.get()
            await self.player.play(next_track)
            changed = await self.wait_for_current_change(old_id)
            self.step("queue_skip", changed is not None,
                      f"now playing: {changed.title}" if changed else "track did not change")
        else:
            self.step("queue_skip", False, "could not load a second track")
        all_ok &= self.steps[-1].ok

        # ---- Step 9: YouTube search (non-fatal, often IP-limited) --------
        try:
            results3 = await wavelink.Playable.search(
                "lofi hip hop", source=wavelink.TrackSource.YouTube)
            tracks3 = list(results3 or [])
            self.step("search_youtube", bool(tracks3),
                      f"{len(tracks3)} results - YouTube source working"
                      if tracks3 else "YouTube returned nothing "
                      "(datacenter IPs are often limited; works on home IPs "
                      "or with cookies/POT config)")
        except Exception as error:
            self.step("search_youtube", False,
                      f"error: {error!r:.120} - may need cookies/POT on this IP")
        # YouTube failures do not fail the whole test (source-dependent).

        # ---- Step 10 (optional): Lavalink kill & auto-recovery ----------
        if os.environ.get("RECOVERY_TEST") == "1":
            all_ok &= await self._recovery_test()

        return all_ok

    async def _recovery_test(self) -> bool:
        """Simulate a Lavalink crash + restart and verify audio recovers.

        The bash harness writes RECOVERY_MARKER; as soon as it appears the
        harness kills Lavalink, waits longer than the 60s session-resume
        window (so resuming is impossible) and starts it again. The bot must
        detect the fresh session, rebuild the voice player automatically and
        continue broadcasting audio.
        """
        before = self.player.current if self.player else None
        if before is None:
            self.step("recovery_setup", False, "no track is playing")
            return False

        marker = os.environ.get("RECOVERY_MARKER", "")
        if marker:
            try:
                with open(marker, "w", encoding="utf-8") as handle:
                    handle.write(str(self.player.position))
            except OSError:
                pass
        log.info("E2E: recovery marker written (%s at %sms) - waiting for "
                 "Lavalink kill + restart...", before.title,
                 self.player.position)

        # Phase 1: the node drops ---------------------------------------
        deadline = time.monotonic() + 90
        dropped = False
        while time.monotonic() < deadline and not dropped:
            nodes = list(wavelink.Pool.nodes.values())
            dropped = (not nodes) or all(
                node.status != wavelink.NodeStatus.CONNECTED
                for node in nodes)
            if not dropped:
                await asyncio.sleep(1)
        if not dropped:
            self.step("lavalink_kill", False,
                      "node never dropped within 90s (was Lavalink killed?")
            return False
        self.step("lavalink_kill", True, "node connection lost as expected")

        # Phase 2: the node comes back -----------------------------------
        deadline = time.monotonic() + 240
        back = False
        while time.monotonic() < deadline and not back:
            nodes = list(wavelink.Pool.nodes.values())
            back = any(node.status == wavelink.NodeStatus.CONNECTED
                       for node in nodes)
            if not back:
                await asyncio.sleep(2)
        if not back:
            self.step("lavalink_restart", False,
                      "node never came back within 240s")
            return False
        self.step("lavalink_restart", True, "node CONNECTED again")

        # Phase 3: the bot must stream again -----------------------------
        deadline = time.monotonic() + 120
        recovered = False
        detail = "no playing player within the recovery window"
        while time.monotonic() < deadline and not recovered:
            voice_client = self.guild.voice_client if self.guild else None
            if isinstance(voice_client, wavelink.Player) \
                    and voice_client.current is not None:
                position_before = voice_client.position
                await asyncio.sleep(3)
                voice_client = (self.guild.voice_client
                                if self.guild else None)
                if isinstance(voice_client, wavelink.Player) \
                        and voice_client.position > position_before:
                    recovered = True
                    same_track = (voice_client.current.identifier
                                  == before.identifier)
                    detail = (f"streaming again: {voice_client.current.title} "
                              f"(same track={same_track}, "
                              f"position={voice_client.position}ms, "
                              f"ping={voice_client.ping}ms)")
                    self.player = voice_client
            else:
                await asyncio.sleep(2)
        self.step("playback_recovered", recovered, detail)
        return recovered

    # ------------------------------------------------------------ utilities
    def _pick_guild(self) -> "Optional[discord.Guild]":
        for guild in self.bot.guilds:
            if guild.me is not None and guild.me.guild_permissions.connect:
                return guild
        return self.bot.guilds[0] if self.bot.guilds else None

    def _pick_voice_channel(self, guild: discord.Guild) -> "Optional[discord.abc.Connectable]":
        wanted = os.environ.get("TEST_VOICE_CHANNEL", "")
        channels = [c for c in guild.voice_channels + guild.stage_channels]
        if wanted:
            for channel in channels:
                if channel.name.lower() == wanted.lower() or str(channel.id) == wanted:
                    return channel
        for channel in channels:
            perms = channel.permissions_for(guild.me)
            if perms.connect and perms.speak:
                return channel
        return channels[0] if channels else None

    async def _cleanup(self) -> None:
        player = None
        if self.guild is not None \
                and isinstance(self.guild.voice_client, wavelink.Player):
            player = self.guild.voice_client
        if player is None and self.player is not None:
            player = self.player
        if player is not None:
            try:
                await player.disconnect()
            except Exception:
                pass

    def report(self) -> bool:
        passed = sum(1 for s in self.steps if s.ok)
        total = len(self.steps)
        all_ok = all(s.ok for s in self.steps)
        log.info("E2E: %s/%s steps passed -> %s", passed, total,
                 "PASS" if all_ok else "FAIL")
        for step in self.steps:
            log.info("E2E:   %-22s %s %s", step.name,
                     "OK " if step.ok else "FAIL", step.detail)
        return all_ok


async def run_auto_test(bot) -> None:
    tester = AutoTest(bot)
    try:
        ok = await tester.run()
        ok = tester.report() and ok
    except Exception:
        log.exception("E2E: crashed")
        ok = False

    result = {
        "ok": ok,
        "steps": [{"name": s.name, "ok": s.ok, "detail": s.detail}
                  for s in tester.steps],
    }
    try:
        with open(RESULT_PATH, "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2)
    except OSError:
        pass

    log.info("E2E: exiting (exit code %s)", 0 if ok else 1)
    await bot.close()
    os._exit(0 if ok else 1)
ZEOF_AUTO_TEST_PY

# ─────────────── مولّد إعدادات Lavalink (ربط داخلي 127.0.0.1) ───────────────
COPY <<'ZEOF_GENCFG_PY' /usr/local/bin/generate_lavalink_config.py
#!/usr/bin/env python3
"""Render /opt/lavalink/application.yml from environment variables.

Lavalink binds to 127.0.0.1 ONLY: the bot runs inside the same container and
talks to it over localhost, so the audio engine is never reachable from the
outside (no exposed port, no public access).
"""
import os
import sys

password = os.getenv("LAVALINK_PASSWORD", "youshallnotpass")
port = os.getenv("LAVALINK_PORT", "2333")
spotify_id = os.getenv("SPOTIFY_CLIENT_ID", "").strip()
spotify_secret = os.getenv("SPOTIFY_CLIENT_SECRET", "").strip()
spotify_enabled = bool(spotify_id and spotify_secret)
# Deezer needs a master key (and an ARL for high-quality formats) - it is
# disabled by default so the container never crashes on startup.
deezer_master_key = os.getenv("DEEZER_MASTER_KEY", "").strip()
deezer_arl = os.getenv("DEEZER_ARL", "").strip()
deezer_enabled = (
    os.getenv("DEEZER_ENABLED", "false").strip().lower() in ("1", "true", "yes", "on")
    and bool(deezer_master_key)
)
# Client order matters: TV is the only client with OAuth playback support
# (the official fix for YouTube's datacenter-IP login wall). WEB stays in the
# chain as a fallback attempt and MUSIC provides ytmsearch. Override freely
# with the YOUTUBE_CLIENTS environment variable.
youtube_clients = os.getenv("YOUTUBE_CLIENTS", "TV,WEB,ANDROID_VR,MUSIC")
clients_lines = "\n".join(f"      - {c.strip()}" for c in youtube_clients.split(",") if c.strip())
# YouTube OAuth refresh token. If empty, the OAuth device flow starts at boot
# and prints the https://www.google.com/device code in the container logs -
# complete it once, then copy the printed refresh token into the
# YOUTUBE_REFRESH_TOKEN environment variable and redeploy.
youtube_oauth_token = os.getenv("YOUTUBE_REFRESH_TOKEN", "").strip()
_oauth_extra = (f'\n      refreshToken: "{youtube_oauth_token}"'
                if youtube_oauth_token else "")
youtube_oauth_block = f"""
    oauth:
      enabled: true{_oauth_extra}"""

spotify_block = ""
if spotify_enabled:
    spotify_block = f"""
      spotify: true
      applemusic: false
      deezer: {str(deezer_enabled).lower()}"""
else:
    spotify_block = f"""
      spotify: false
      applemusic: false
      deezer: {str(deezer_enabled).lower()}"""

spotify_config = ""
if spotify_enabled:
    spotify_config = f"""
    spotify:
      clientId: "{spotify_id}"
      clientSecret: "{spotify_secret}"
      countrycode: "{os.getenv('SPOTIFY_COUNTRY', 'US')}"
      playlistLoadLimit: 6
      albumLoadLimit: 6"""

deezer_config = ""
if deezer_enabled:
    deezer_config = f"""
    deezer:
      formats: ["MP3_320", "MP3_128"]
      masterKey: "{deezer_master_key}"""
    if deezer_arl:
        deezer_config += f"""
      arl: "{deezer_arl}"""

yaml = f"""server:
  port: {port}
  address: 127.0.0.1

lavalink:
  server:
    password: "{password}"
    sources:
      youtube: false
      soundcloud: true
      bandcamp: true
      twitch: true
      vimeo: true
      http: true
      local: false
    nonAllocatingFrameBuffer: true
    playerUpdateInterval: 5
    youtubePlaylistLoadLimit: 6

  plugins:
    - dependency: "dev.lavalink.youtube:youtube-plugin:1.18.2"
      snapshot: false
    - dependency: "com.github.topi314.lavasrc:lavasrc-plugin:4.8.3"
      snapshot: false

plugins:
  youtube:
    allowSearch: true
    allowDirectVideoIds: true
    allowDirectPlaylistIds: true
    clients:
{clients_lines}{youtube_oauth_block}
  lavasrc:
    providers:
      - "ytsearch:\\"%ISRC%\\""
      - "ytsearch:%ISRC%"
      - "ytsearch:%QUERY%"
    sources:{spotify_block}
      flowerytts: false
      youtube: false
    lyrics-sources:
      spotify: {str(spotify_enabled).lower()}
      deezer: {str(deezer_enabled).lower()}{spotify_config}{deezer_config}

logging:
  file:
    path: /opt/lavalink/logs/
  logback:
    rollingpolicy:
      max-file-size: 25MB
      max-history: 2
  level:
    root: INFO
    lavalink: INFO
"""

with open("/opt/lavalink/application.yml", "w", encoding="utf-8") as handle:
    handle.write(yaml)
print("application.yml written "
      f"(spotify={'ON' if spotify_enabled else 'OFF'}, "
      f"deezer={'ON' if deezer_enabled else 'OFF'}, bind=127.0.0.1)",
      file=sys.stderr)
ZEOF_GENCFG_PY

# ─────────────── نقطة الدخول الذاتية الإصلاح (MariaDB → Lavalink → البوت) ───────────────
COPY <<'ZEOF_ENTRYPOINT_SH' /entrypoint.sh
#!/bin/bash
# ═══ All-in-one self-healing entrypoint: MariaDB -> Lavalink v4 -> bot ═══
set -u

DISCORD_TOKEN="${DISCORD_TOKEN:-${BOT_TOKEN:-}}"
if [ -z "$DISCORD_TOKEN" ]; then
    echo "ERROR: DISCORD_TOKEN is missing!"
    echo "Set it in the Dockerfile (ENV DISCORD_TOKEN) or as a Railway variable."
    sleep 5
    exit 1
fi
export DISCORD_TOKEN

DB_USER="${DB_USER:-musicbot}"
DB_PASSWORD="${DB_PASSWORD:-musicbotpass}"
DB_NAME="${DB_NAME:-musicbot}"
DATADIR="/var/lib/mysql"
SOCKET="/var/run/mysqld/mysqld.sock"
MDB_PID=""
LL_PID=""

shutdown() {
    echo "[entrypoint] Shutting down..."
    [ -n "$LL_PID" ] && kill "$LL_PID" 2>/dev/null
    [ -n "$MDB_PID" ] && kill "$MDB_PID" 2>/dev/null
    exit 0
}
trap shutdown TERM INT

start_mariadb() {
    if [ ! -d "$DATADIR/mysql" ]; then
        echo "[entrypoint] Initializing MariaDB data directory..."
        mariadb-install-db --user=mysql --datadir="$DATADIR" \
            --auth-root-authentication-method=normal --skip-test-db >/dev/null 2>&1
    fi
    chown -R mysql:mysql "$DATADIR" 2>/dev/null || true
    echo "[entrypoint] Starting MariaDB (memory-tuned)..."
    mariadbd --user=mysql --datadir="$DATADIR" --socket="$SOCKET" \
        --bind-address=127.0.0.1 --port="${DB_PORT:-3306}" \
        --skip-name-resolve --performance-schema=OFF \
        --innodb_buffer_pool_size="${INNODB_BUFFER_POOL_SIZE:-64M}" \
        --key_buffer_size=8M --max_connections=25 &
    MDB_PID=$!
    for i in $(seq 1 60); do
        if mariadb-admin --socket="$SOCKET" -u root ping >/dev/null 2>&1; then
            echo "[entrypoint] MariaDB is ready."
            break
        fi
        if ! kill -0 "$MDB_PID" 2>/dev/null; then
            echo "[entrypoint] FATAL: mariadbd died during startup."
            exit 1
        fi
        sleep 1
    done
    mariadb --socket="$SOCKET" -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL
}

start_lavalink() {
    echo "[entrypoint] Generating Lavalink config (binds to 127.0.0.1 only)..."
    generate_lavalink_config.py
    cd /opt/lavalink
    echo "[entrypoint] Starting Lavalink v4..."
    java -Xmx"${LAVALINK_HEAP:-512m}" -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError \
        -jar Lavalink.jar > /opt/lavalink/logs/stdout.log 2>&1 &
    LL_PID=$!
    cd /app
    for i in $(seq 1 300); do
        code=$(curl -s -o /dev/null -w "%{http_code}" -m 2 \
            -H "Authorization: ${LAVALINK_PASSWORD:-youshallnotpass}" \
            "http://127.0.0.1:${LAVALINK_PORT:-2333}/version" 2>/dev/null || echo 000)
        if [ "$code" = "200" ]; then
            echo "[entrypoint] Lavalink v4 is ready (took ${i}s)."
            return 0
        fi
        if ! kill -0 "$LL_PID" 2>/dev/null; then
            echo "[entrypoint] FATAL: Lavalink died during startup. Last log lines:"
            tail -30 /opt/lavalink/logs/stdout.log
            exit 1
        fi
        sleep 1
    done
    echo "[entrypoint] FATAL: Lavalink not ready after 300s. Last log lines:"
    tail -30 /opt/lavalink/logs/stdout.log
    exit 1
}

component_supervisor() {
    # If MariaDB or Lavalink die at runtime, restart them automatically.
    while true; do
        sleep 20
        if ! kill -0 "$MDB_PID" 2>/dev/null; then
            echo "[supervisor] MariaDB is down - restarting it."
            start_mariadb
        fi
        if ! kill -0 "$LL_PID" 2>/dev/null; then
            echo "[supervisor] Lavalink is down - restarting it."
            tail -5 /opt/lavalink/logs/stdout.log 2>/dev/null || true
            start_lavalink
        fi
    done
}

start_mariadb
start_lavalink
component_supervisor &
SUP_PID=$!

# The bot itself: restart with backoff on crashes. Exit codes 2/3/4 are
# permanent configuration problems -> stop instead of looping forever.
BACKOFF=5
while true; do
    cd /app
    python3 main.py
    code=$?
    case "$code" in
        2|3|4)
            echo "[entrypoint] FATAL bot configuration problem (exit $code):"
            echo "   2 = missing/invalid config, 3 = privileged intents disabled,"
            echo "   4 = invalid Discord token. Fix the token and redeploy."
            break
            ;;
        *)
            echo "[entrypoint] Bot exited (code $code) - restarting in ${BACKOFF}s..."
            sleep "$BACKOFF"
            if [ "$BACKOFF" -lt 60 ]; then BACKOFF=$((BACKOFF * 2)); fi
            ;;
    esac
done
ZEOF_ENTRYPOINT_SH

RUN chmod 755 /usr/local/bin/generate_lavalink_config.py /entrypoint.sh

# ─────────────── الإعدادات الافتراضية ───────────────

# ⚠️ توكن البوت: غيّر القيمة هنا عند الحاجة (أو تجاوزها بمتغير Railway
#    باسم DISCORD_TOKEN وستكون لها الأولوية).
ENV DISCORD_TOKEN="MTM3NTYzNDc0OTM0MjYxMzYwNA.GurQ-I.dzaqNIZrgYlyrN2g6X_JQ3BGsCvIGqKoj5s03U"

# يوتيوب OAuth: الحل الرسمي لخطأ "This video requires login" الناتج عن حجب
# يوتيوب لعناوين IP السحابية (مثل Railway). القيمة المدمجة أدناه توكن حساب
# YouTube مربوط مسبقاً. لتحديثه لاحقاً: ضع متغير YOUTUBE_REFRESH_TOKEN في
# Railway (له الأولوية) أو بدّل القيمة هنا. إن تُرك فارغاً سيطبع اللوج كود
# ربط عند الإقلاع تُكمليه على https://www.google.com/device
ENV YOUTUBE_REFRESH_TOKEN="1//0eVooXRETOIiuCgYIARAAGA4SNwF-L9Irvn8-fFnEvPQl33FHJroxf7YbO4WmJ2Go52l3IrBkRh7BIPIiuX0FyGmgo7lAeC9krzw"

ENV DB_TYPE=mysql \
    DB_HOST=127.0.0.1 \
    DB_PORT=3306 \
    DB_USER=musicbot \
    DB_PASSWORD=musicbotpass \
    DB_NAME=musicbot \
    LAVALINK_HOST=127.0.0.1 \
    LAVALINK_PORT=2333 \
    LAVALINK_PASSWORD=youshallnotpass \
    PREFIX=? \
    DEFAULT_VOLUME=60 \
    MAX_VOLUME=150 \
    AUTO_DISCONNECT_SECONDS=300

# بيانات MariaDB تُخزَّن داخل نظام ملفات الحاوية (مؤقتة — تُعاد تهيئتها عند
# إعادة النشر، وهذا مقبول تماماً لبوت موسيقي). للحفاظ على الطابور وقوائم
# التشغيل بعد إعادة النشر على Railway: من إعدادات الخدمة ← Volumes أضيفي
# Volume واربطيه بالمسار /var/lib/mysql — لا حاجة لأي تعديل في هذا الملف.
# ملاحظة: Railway لا يدعم تعليمة VOLUME داخل Dockerfile، لذلك حُذفت عمداً.

# ملاحظة: لا يوجد EXPOSE — المنفذ 2333 داخلي فقط كما هو مطلوب.

HEALTHCHECK --interval=30s --timeout=10s --start-period=240s --retries=5 \
    CMD curl -fsS -H "Authorization: ${LAVALINK_PASSWORD}" \
        "http://127.0.0.1:${LAVALINK_PORT}/version" >/dev/null \
    && pgrep -f "python3 main.py" >/dev/null

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
