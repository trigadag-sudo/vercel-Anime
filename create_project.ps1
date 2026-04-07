Param()
Set-StrictMode -Version Latest

$root = "C:\anime-ua-vercel"
$zip = "$root.zip"

if (Test-Path $root) {
  Write-Host "Папка $root вже існує. Видаліть або перейменуйте її перед запуском." -ForegroundColor Yellow
  exit 1
}

New-Item -Path $root -ItemType Directory -Force | Out-Null

function Write-File([string]$Path, [string]$Content) {
  $dir = Split-Path $Path -Parent
  if ($dir -and !(Test-Path $dir)) {
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
  }
  $Content | Out-File -FilePath $Path -Encoding utf8
}

Write-Host "Створюю структуру проекту..." -ForegroundColor Green

# Root files
Write-File "$root\README.md" @'
# anime-ua-vercel

Готовий стартовий шаблон Next.js + Prisma + PostgreSQL + Cloudflare R2 (S3) для каталогу аніме.

## Швидкий старт
1. Скопіюй `.env.example` у `.env`.
2. Підніми PostgreSQL (локально або в Docker).
3. Встанови залежності:
   npm install
4. Створи Prisma client і міграції:
   npx prisma generate
   npx prisma migrate dev --name init
5. Заповни тестові дані:
   npm run seed
6. Запусти застосунок:
   npm run dev

## API
- `POST /api/auth/login` — отримати JWT через `apiKey`
- `GET /api/anime` — список аніме
- `POST /api/anime` — створити аніме (потрібен Bearer JWT)
- `GET /api/anime/[id]` — аніме з епізодами
- `GET /api/episodes/[id]/stream?audio=uk` — URL для стріму

## Перевірка авторизації
1. Отримати токен:
   curl -X POST http://localhost:3000/api/auth/login -H "Content-Type: application/json" -d "{\"apiKey\":\"supersecretkey\"}"
2. Створити аніме:
   curl -X POST http://localhost:3000/api/anime -H "Authorization: Bearer <JWT>" -H "Content-Type: application/json" -d "{\"titleOriginal\":\"Naruto\",\"titleLocal\":\"Наруто\",\"year\":2002}"
- `GET /api/anime` — список аніме
- `GET /api/anime/[id]` — аніме з епізодами
- `GET /api/episodes/[id]/stream?audio=uk` — URL для стріму
'@

Write-File "$root\.env.example" @'
DATABASE_URL=postgresql://USER:PASSWORD@localhost:5432/anime?schema=public
API_KEY=supersecretkey
JWT_SECRET=dev_jwt_secret
JWT_EXPIRES_IN=7d

S3_ENDPOINT=https://<accountid>.r2.cloudflarestorage.com
S3_BUCKET=anime-media
S3_REGION=auto
S3_ACCESS_KEY=your_r2_access_key
S3_SECRET_KEY=your_r2_secret_key

NEXT_PUBLIC_API_BASE_URL=/api
'@

Write-File "$root\package.json" @'
{
  "name": "anime-ua-vercel",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev -p 3000",
    "build": "next build",
    "start": "next start -p 3000",
    "postinstall": "prisma generate",
    "seed": "ts-node --transpile-only prisma/seed.ts"
  },  "prisma": {
    "seed": "ts-node --transpile-only prisma/seed.ts"
  },
  "dependencies": {
    "next": "14.0.0",
    "react": "18.2.0",
    "react-dom": "18.2.0",
    "aws-sdk": "^2.1360.0",
    "@prisma/client": "^5.0.0",
    "jsonwebtoken": "^9.0.2"
    "@prisma/client": "^5.0.0"
  },
  "devDependencies": {
    "prisma": "^5.0.0",
    "ts-node": "^10.9.1",
    "typescript": "^5.4.0"
  }
}
'@

Write-File "$root\next.config.js" @'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  env: {
    NEXT_PUBLIC_API_BASE_URL: process.env.NEXT_PUBLIC_API_BASE_URL || '/api'
  }
}

module.exports = nextConfig
'@

# Prisma
Write-File "$root\prisma\schema.prisma" @'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model Anime {
  id            Int       @id @default(autoincrement())
  titleOriginal String
  titleLocal    String?
  description   String?
  year          Int?
  posterUrl     String?
  createdAt     DateTime  @default(now())
  updatedAt     DateTime  @updatedAt
  episodes      Episode[]
}

model Episode {
  id            Int      @id @default(autoincrement())
  animeId        Int
  episodeNumber  Int
  title          String?
  audioUkUrl     String
  audioJpUrl     String?
  subtitleUkUrl  String?
  anime          Anime   @relation(fields: [animeId], references: [id])
}
'@

Write-File "$root\prisma\seed.ts" @'
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  await prisma.anime.create({
    data: {
      titleOriginal: "Shingeki no Kyojin",
      titleLocal: "Атака Титанів",
      description: "Демо запис для старту проекту.",
      year: 2013,
      posterUrl: "https://placehold.co/320x480?text=Anime",
      episodes: {
        create: [
          {
            episodeNumber: 1,
            title: "To You, in 2000 Years",
            audioUkUrl: "videos/attack_s1_e1_uk.mp3",
            audioJpUrl: "videos/attack_s1_e1_jp.mp3",
            subtitleUkUrl: "subtitles/attack_s1_e1_uk.vtt"
          }
        ]
      }
    }
  });

  console.log("Seed completed");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
'@

# src/lib
Write-File "$root\src\lib\prisma.js" @'
import { PrismaClient } from "@prisma/client";

const globalForPrisma = global;

export const prisma = globalForPrisma.prisma || new PrismaClient();

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}
'@

Write-File "$root\src\lib\s3.js" @'
import AWS from "aws-sdk";

const s3 = new AWS.S3({
  endpoint: process.env.S3_ENDPOINT,
  accessKeyId: process.env.S3_ACCESS_KEY,
  secretAccessKey: process.env.S3_SECRET_KEY,
  s3ForcePathStyle: true,
  signatureVersion: "v4",
  region: process.env.S3_REGION || "auto"
});

export async function getSignedUrl(key, expires = 3600) {
  return s3.getSignedUrlPromise("getObject", {
    Bucket: process.env.S3_BUCKET,
    Key: key,
    Expires: expires
  });
}
'@

Write-File "$root\src\lib\jwt.js" @'
import jwt from "jsonwebtoken";

const JWT_SECRET = process.env.JWT_SECRET || "dev_jwt_secret";
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || "7d";

export function sign(payload) {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

export function verify(token) {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch {
    return null;
  }
}
'@

# src/pages/api
Write-File "$root\src\pages\api\auth\login.js" @'
import { sign } from "../../../../lib/jwt";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", ["POST"]);
    return res.status(405).end();
  }

  const { apiKey } = req.body || {};
  if (!apiKey || apiKey !== process.env.API_KEY) {
    return res.status(401).json({ error: "Invalid API key" });
  }

  const token = sign({ role: "admin" });
  return res.status(200).json({ token });
}
'@

Write-File "$root\src\pages\api\anime\index.js" @'
import { prisma } from "../../../lib/prisma";
import { verify } from "../../../lib/jwt";

export default async function handler(req, res) {
  if (req.method === "GET") {
    const list = await prisma.anime.findMany({
      select: {
        id: true,
        titleOriginal: true,
        titleLocal: true,
        year: true,
        posterUrl: true
      },
      orderBy: { id: "desc" }
    });

    return res.status(200).json(list);
  }

  if (req.method === "POST") {
    const auth = req.headers.authorization || "";
    const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
    const payload = verify(token);
    if (!payload || payload.role !== "admin") {
      return res.status(401).json({ error: "Unauthorized" });
    }

    const { titleOriginal, titleLocal, description, year, posterUrl } = req.body || {};
    if (!titleOriginal) {
      return res.status(400).json({ error: "titleOriginal is required" });
    }

    const created = await prisma.anime.create({
      data: {
        titleOriginal,
        titleLocal: titleLocal || null,
        description: description || null,
        year: Number.isInteger(year) ? year : null,
        posterUrl: posterUrl || null
      }
    });

    return res.status(201).json(created);
  }

  res.setHeader("Allow", ["GET", "POST"]);
  return res.status(405).end();
# src/pages/api
Write-File "$root\src\pages\api\anime\index.js" @'
import { prisma } from "../../../../lib/prisma";

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", ["GET"]);
    return res.status(405).end();
  }

  const list = await prisma.anime.findMany({
    select: {
      id: true,
      titleOriginal: true,
      titleLocal: true,
      year: true,
      posterUrl: true
    },
    orderBy: { id: "desc" }
  });

  return res.status(200).json(list);
}
'@

Write-File "$root\src\pages\api\anime\[id].js" @'
import { prisma } from "../../../lib/prisma";
import { prisma } from "../../../../lib/prisma";

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", ["GET"]);
    return res.status(405).end();
  }

  const id = Number(req.query.id);
  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: "Invalid id" });
  }

  const anime = await prisma.anime.findUnique({
    where: { id },
    include: {
      episodes: {
        orderBy: { episodeNumber: "asc" }
      }
    }
  });

  if (!anime) {
    return res.status(404).json({ error: "Not found" });
  }

  return res.status(200).json(anime);
}
'@

Write-File "$root\src\pages\api\episodes\[id]\stream.js" @'
import { prisma } from "../../../../lib/prisma";
import { getSignedUrl } from "../../../../lib/s3";
import { prisma } from "../../../../../lib/prisma";
import { getSignedUrl } from "../../../../../lib/s3";

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", ["GET"]);
    return res.status(405).end();
  }

  const id = Number(req.query.id);
  const audio = (req.query.audio || "uk").toLowerCase();

  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: "Invalid id" });
  }

  const episode = await prisma.episode.findUnique({ where: { id } });
  if (!episode) {
    return res.status(404).json({ error: "Episode not found" });
  }

  const fileKey = audio === "jp" && episode.audioJpUrl ? episode.audioJpUrl : episode.audioUkUrl;
  let url = fileKey;

  if (!fileKey.startsWith("http")) {
    url = await getSignedUrl(fileKey, 3600);
  }

  return res.status(200).json({
    url,
    subtitles: episode.subtitleUkUrl
      ? [{ language: "uk", fileUrl: episode.subtitleUkUrl }]
      : []
  });
}
'@

# src/pages
Write-File "$root\src\pages\index.jsx" @'
import Catalog from "../components/Catalog";

export default function HomePage() {
  return <Catalog />;
}
'@

Write-File "$root\src\pages\anime\[id].jsx" @'
import { useRouter } from "next/router";
import { useEffect, useState } from "react";
import Player from "../../components/Player";

export default function AnimePage() {
  const { query } = useRouter();
  const [anime, setAnime] = useState(null);

  useEffect(() => {
    if (!query.id) return;
    fetch(`/api/anime/${query.id}`)
      .then((r) => r.json())
      .then(setAnime);
  }, [query.id]);

  if (!anime) return <div style={{ padding: 20 }}>Завантаження...</div>;

  return (
    <div style={{ padding: 20 }}>
      <h1>{anime.titleLocal || anime.titleOriginal}</h1>
      <p>{anime.description}</p>

      {anime.episodes.map((ep) => (
        <div key={ep.id} style={{ marginBottom: 16 }}>
          <strong>Епізод {ep.episodeNumber}: {ep.title || "Без назви"}</strong>
          <Player episodeId={ep.id} />
        </div>
      ))}
    </div>
  );
}
'@

# src/components
Write-File "$root\src\components\AnimeCard.jsx" @'
import Link from "next/link";

export default function AnimeCard({ anime }) {
  return (
    <div style={{ border: "1px solid #ddd", borderRadius: 8, padding: 12 }}>
      <h3>{anime.titleLocal || anime.titleOriginal}</h3>
      <p>{anime.year || "—"}</p>
      <Link href={`/anime/${anime.id}`}>Деталі</Link>
    </div>
  );
}
'@

Write-File "$root\src\components\Catalog.jsx" @'
import { useEffect, useState } from "react";
import AnimeCard from "./AnimeCard";

export default function Catalog() {
  const [items, setItems] = useState([]);

  useEffect(() => {
    fetch("/api/anime")
      .then((r) => r.json())
      .then(setItems);
  }, []);

  return (
    <main style={{ padding: 20 }}>
      <h1>Каталог аніме</h1>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 12 }}>
        {items.map((anime) => (
          <AnimeCard key={anime.id} anime={anime} />
        ))}
      </div>
    </main>
  );
}
'@

Write-File "$root\src\components\Player.jsx" @'
import { useState } from "react";

export default function Player({ episodeId }) {
  const [src, setSrc] = useState(null);
  const [loading, setLoading] = useState(false);

  async function loadAudio(lang) {
    setLoading(true);
    const res = await fetch(`/api/episodes/${episodeId}/stream?audio=${lang}`);
    const data = await res.json();
    setLoading(false);

    if (data.url) {
      setSrc(data.url);
    } else {
      alert(data.error || "Не вдалося завантажити аудіо");
    }
  }

  return (
    <div style={{ marginTop: 8 }}>
      <div style={{ display: "flex", gap: 8, marginBottom: 8 }}>
        <button onClick={() => loadAudio("uk")}>UA</button>
        <button onClick={() => loadAudio("jp")}>JP</button>
      </div>

      {loading && <div>Завантаження...</div>}

      {src ? (
        <audio controls src={src} style={{ width: "100%" }} />
      ) : (
        <div style={{ color: "#666" }}>Оберіть звукову доріжку</div>
      )}
    </div>
  );
}
'@

# scripts
Write-File "$root\scripts\deploy_notes.md" @'
Deploy notes:

1) Додайте env у Vercel:
- DATABASE_URL
- S3_ENDPOINT
- S3_BUCKET
- S3_REGION
- S3_ACCESS_KEY
- S3_SECRET_KEY
- NEXT_PUBLIC_API_BASE_URL

2) Build command:
npm run build

3) Після першого деплою виконайте:
npx prisma migrate deploy
npx prisma db seed
'@

# ZIP
Write-Host "Пакую проект у ZIP..." -ForegroundColor Green
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $zip) { Remove-Item $zip -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($root, $zip)

Write-Host "Готово: $zip" -ForegroundColor Cyan
