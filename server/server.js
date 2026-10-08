import express from "express";
import cors from "cors";
import multer from "multer";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import ffmpeg from "fluent-ffmpeg";
import ffmpegStatic from "ffmpeg-static";
import ytDlp from "yt-dlp-exec";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 10000;

ffmpeg.setFfmpegPath(ffmpegStatic);

const uploadsDir = path.join(__dirname, "uploads");
const outputsDir = path.join(__dirname, "outputs");

fs.mkdirSync(uploadsDir, { recursive: true });
fs.mkdirSync(outputsDir, { recursive: true });

app.use(cors());
app.use(express.json({ limit: "10mb" }));
app.use("/outputs", express.static(outputsDir));

const upload = multer({
  dest: uploadsDir,
  limits: {
    fileSize: 500 * 1024 * 1024,
  },
});

app.get("/", (req, res) => {
  res.json({
    status: "ok",
    message: "ClipAI server is running",
  });
});

/* ----------------------------- */
/* Helpers */
/* ----------------------------- */

function safeNumber(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function cleanup(file) {
  try {
    if (file && fs.existsSync(file)) {
      fs.unlinkSync(file);
    }
  } catch {}
}

function extractJson(text) {
  let cleaned = String(text || "").trim();

  cleaned = cleaned
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  const first = cleaned.indexOf("{");
  const last = cleaned.lastIndexOf("}");

  if (first !== -1 && last !== -1) {
    cleaned = cleaned.slice(first, last + 1);
  }

  return JSON.parse(cleaned);
}

/* ----------------------------- */
/* Gemini */
/* ----------------------------- */

async function geminiRequest(prompt) {
  const apiKey = process.env.GEMINI_API_KEY;

  if (!apiKey) {
    throw new Error("GEMINI_API_KEY is not configured on Render.");
  }

  const models = [
    "gemini-2.5-flash",
    "gemini-2.0-flash",
  ];

  let lastError = null;

  for (const model of models) {
    try {
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            contents: [
              {
                parts: [
                  {
                    text: prompt,
                  },
                ],
              },
            ],
            generationConfig: {
              temperature: 0.2,
              responseMimeType: "application/json",
            },
          }),
        }
      );

      const data = await response.json();

      if (!response.ok) {
        lastError = new Error(
          `Gemini ${model} error ${response.status}: ${
            data?.error?.message || JSON.stringify(data)
          }`
        );
        continue;
      }

      const text =
        data?.candidates?.[0]?.content?.parts
          ?.map((p) => p.text || "")
          .join("") || "";

      if (!text) {
        throw new Error("Gemini returned an empty response.");
      }

      return text;
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError || new Error("Gemini request failed.");
}

/* ----------------------------- */
/* Video information */
/* ----------------------------- */

function getVideoDuration(videoPath) {
  return new Promise((resolve, reject) => {
    ffmpeg.ffprobe(videoPath, (error, metadata) => {
      if (error) {
        reject(error);
        return;
      }

      const duration = Number(metadata?.format?.duration || 0);

      if (!duration) {
        reject(new Error("Could not determine video duration."));
        return;
      }

      resolve(duration);
    });
  });
}

/* ----------------------------- */
/* Extract audio */
/* ----------------------------- */

function extractAudio(videoPath, audioPath) {
  return new Promise((resolve, reject) => {
    ffmpeg(videoPath)
      .noVideo()
      .audioCodec("pcm_s16le")
      .audioFrequency(16000)
      .audioChannels(1)
      .format("wav")
      .on("end", resolve)
      .on("error", reject)
      .save(audioPath);
  });
}

/* ----------------------------- */
/* Transcription */
/* ----------------------------- */

/*
  This expects the server to have a Whisper executable available.

  Environment variable:
  WHISPER_COMMAND

  Example:
  whisper

  The actual command can be configured on Render later.
*/

async function transcribeAudio(audioPath) {
  const whisperCommand = process.env.WHISPER_COMMAND || "whisper";

  const transcriptDir = path.join(
    uploadsDir,
    `transcript-${Date.now()}`
  );

  fs.mkdirSync(transcriptDir, { recursive: true });

  try {
    const { spawn } = await import("child_process");

    await new Promise((resolve, reject) => {
      const args = [
        audioPath,
        "--model",
        "base",
        "--output_format",
        "json",
        "--output_dir",
        transcriptDir,
        "--language",
        "en",
      ];

      const process = spawn(whisperCommand, args);

      let stderr = "";

      process.stderr.on("data", (data) => {
        stderr += data.toString();
      });

      process.on("error", reject);

      process.on("close", (code) => {
        if (code === 0) {
          resolve();
        } else {
          reject(
            new Error(
              `Whisper failed with exit code ${code}: ${stderr}`
            )
          );
        }
      });
    });

    const jsonFiles = fs
      .readdirSync(transcriptDir)
      .filter((file) => file.endsWith(".json"));

    if (!jsonFiles.length) {
      throw new Error("Whisper did not produce a transcript JSON file.");
    }

    const transcriptFile = path.join(
      transcriptDir,
      jsonFiles[0]
    );

    const data = JSON.parse(
      fs.readFileSync(transcriptFile, "utf8")
    );

    const segments = Array.isArray(data.segments)
      ? data.segments
          .map((segment) => ({
            start: Number(segment.start || 0),
            end: Number(segment.end || 0),
            text: String(segment.text || "").trim(),
          }))
          .filter((segment) => segment.text)
      : [];

    if (!segments.length) {
      throw new Error("No speech was detected in the video.");
    }

    return segments;
  } finally {
    fs.rmSync(transcriptDir, {
      recursive: true,
      force: true,
    });
  }
}

/* ----------------------------- */
/* Gemini clip selection */
/* ----------------------------- */

async function findBestClips(segments, numberOfClips, duration) {
  const transcript = segments
    .map(
      (s) =>
        `[${s.start.toFixed(2)} - ${s.end.toFixed(2)}] ${s.text}`
    )
    .join("\n");

  const prompt = `
You are the AI clip-selection engine for ClipAI.

Analyze this transcript and find the ${numberOfClips} strongest moments
for YouTube Shorts / TikTok / Instagram Reels.

Goal:
Choose moments that have a strong hook, emotion, curiosity,
useful information, surprising statements, conflict, storytelling,
or a satisfying payoff.

Rules:

1. Each clip must be between 20 and 60 seconds.
2. Use the exact timestamps from the transcript.
3. Do not invent timestamps.
4. Clips must stay inside the video duration.
5. Prefer moments that can work independently.
6. Avoid introductions, greetings, silence and filler.
7. Avoid overlapping clips.
8. Start as close as possible to the beginning of the interesting statement.
9. End after the payoff, not in the middle of a sentence.
10. Rank the clips by viral potential.

Return ONLY valid JSON:

{
  "clips": [
    {
      "start": 0,
      "end": 30,
      "score": 95,
      "title": "Short descriptive title",
      "reason": "Why this moment is strong"
    }
  ]
}

Video duration: ${duration} seconds.

TRANSCRIPT:
${transcript}
`;

  const raw = await geminiRequest(prompt);

  const parsed = extractJson(raw);

  if (!Array.isArray(parsed.clips)) {
    throw new Error("Gemini did not return a clips array.");
  }

  const clips = parsed.clips
    .map((clip) => ({
      start: Math.max(0, safeNumber(clip.start, 0)),
      end: Math.min(
        duration,
        safeNumber(clip.end, 0)
      ),
      score: safeNumber(clip.score, 0),
      title: String(clip.title || "Clip"),
      reason: String(clip.reason || ""),
    }))
    .filter(
      (clip) =>
        clip.end > clip.start &&
        clip.end - clip.start >= 20 &&
        clip.end - clip.start <= 60
    )
    .sort((a, b) => b.score - a.score);

  return clips.slice(0, numberOfClips);
}

/* ----------------------------- */
/* Create MP4 clip */
/* ----------------------------- */

function createClip(input, output, start, duration, format) {
  return new Promise((resolve, reject) => {
    let command = ffmpeg(input)
      .seekInput(start)
      .duration(duration)
      .videoCodec("libx264")
      .audioCodec("aac")
      .outputOptions([
        "-preset",
        "veryfast",
        "-crf",
        "23",
        "-movflags",
        "+faststart",
      ]);

    /*
      9:16 vertical crop.
      We keep the original center for now.
      Later we can add AI face tracking.
    */

    if (format === "9:16") {
      command = command
        .videoFilters(
          "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920"
        );
    }

    if (format === "1:1") {
      command = command
        .videoFilters(
          "scale=1080:1080:force_original_aspect_ratio=increase,crop=1080:1080"
        );
    }

    if (format === "16:9") {
      command = command
        .videoFilters(
          "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080"
        );
    }

    command
      .on("end", resolve)
      .on("error", reject)
      .save(output);
  });
}

/* ----------------------------- */
/* Download YouTube */
/* ----------------------------- */

async function downloadYouTube(url, outputBase) {
  const allowedHosts = [
    "youtube.com",
    "www.youtube.com",
    "youtu.be",
    "m.youtube.com",
  ];

  const parsed = new URL(url);

  if (!allowedHosts.includes(parsed.hostname)) {
    throw new Error("Only YouTube URLs are supported.");
  }

  const output = `${outputBase}.%(ext)s`;

  await ytDlp(url, {
    output,
    format: "best[height<=720]/best",
    mergeOutputFormat: "mp4",
    noPlaylist: true,
    noWarnings: true,
    quiet: true,
    restrictFilenames: true,
    ffmpegLocation: ffmpegStatic,
  });

  const files = fs
    .readdirSync(uploadsDir)
    .filter((file) =>
      file.startsWith(path.basename(outputBase))
    );

  if (!files.length) {
    throw new Error("YouTube video was not downloaded.");
  }

  return path.join(uploadsDir, files[0]);
}

/* ----------------------------- */
/* Analyze */
/* ----------------------------- */

app.post(
  "/api/analyze",
  upload.single("video"),
  async (req, res) => {
    let videoPath = null;
    let audioPath = null;

    try {
      const url = String(req.body?.url || "").trim();

      const numberOfClips = Math.min(
        15,
        Math.max(
          1,
          parseInt(req.body?.numberOfClips || "5", 10)
        )
      );

      const format = String(
        req.body?.format || "9:16"
      );

      if (req.file) {
        videoPath = req.file.path;
      } else if (url) {
        const base = path.join(
          uploadsDir,
          `download-${Date.now()}`
        );

        videoPath = await downloadYouTube(
          url,
          base
        );
      } else {
        return res.status(400).json({
          error: "Upload a video or provide a YouTube URL.",
        });
      }

      const duration = await getVideoDuration(
        videoPath
      );

      audioPath = path.join(
        uploadsDir,
        `audio-${Date.now()}.wav`
      );

      await extractAudio(
        videoPath,
        audioPath
      );

      const segments = await transcribeAudio(
        audioPath
      );

      const clips = await findBestClips(
        segments,
        numberOfClips,
        duration
      );

      if (!clips.length) {
        throw new Error(
          "AI could not find suitable clips."
        );
      }

      const results = [];

      for (let i = 0; i < clips.length; i++) {
        const clip = clips[i];

        const outputName =
          `clip-${Date.now()}-${i + 1}.mp4`;

        const outputPath = path.join(
          outputsDir,
          outputName
        );

        await createClip(
          videoPath,
          outputPath,
          clip.start,
          clip.end - clip.start,
          format
        );

        results.push({
          id: i + 1,
          title: clip.title,
          reason: clip.reason,
          score: clip.score,
          start: clip.start,
          end: clip.end,
          duration:
            clip.end - clip.start,
          url:
            `${req.protocol}://${req.get("host")}/outputs/${outputName}`,
        });
      }

      return res.json({
        success: true,
        ai: "gemini",
        duration,
        clips: results,
      });
    } catch (error) {
      console.error(error);

      return res.status(500).json({
        error:
          error?.message ||
          "Server error",
      });
    } finally {
      cleanup(videoPath);
      cleanup(audioPath);
    }
  }
);

app.listen(PORT, () => {
  console.log(
    `ClipAI server running on port ${PORT}`
  );
});
