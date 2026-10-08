import express from "express";
import cors from "cors";
import multer from "multer";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import ffmpeg from "fluent-ffmpeg";
import ffmpegStatic from "ffmpeg-static";
import ytDlp from "yt-dlp-exec";
import { GoogleGenAI } from "@google/genai";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 10000;

ffmpeg.setFfmpegPath(ffmpegStatic);

const ai = new GoogleGenAI({
  apiKey: process.env.GEMINI_API_KEY,
});

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
    ai: "Gemini",
  });
});

function cleanup(file) {
  try {
    if (file && fs.existsSync(file)) {
      fs.unlinkSync(file);
    }
  } catch {}
}

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

function extractJson(text) {
  let result = String(text || "").trim();

  result = result
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  const start = result.indexOf("{");
  const end = result.lastIndexOf("}");

  if (start !== -1 && end !== -1) {
    result = result.substring(start, end + 1);
  }

  return JSON.parse(result);
}

/* ================================= */
/* GEMINI VIDEO ANALYSIS */
/* ================================= */

async function analyzeVideoWithGemini(videoPath, numberOfClips) {
  if (!process.env.GEMINI_API_KEY) {
    throw new Error("GEMINI_API_KEY is missing on Render.");
  }

  console.log("Uploading video to Gemini...");

  let videoFile = await ai.files.upload({
    file: videoPath,
    config: {
      mimeType: "video/mp4",
    },
  });

  console.log("Gemini file:", videoFile.name);

  while (videoFile.state === "PROCESSING") {
    console.log("Gemini is processing the video...");

    await new Promise((resolve) =>
      setTimeout(resolve, 3000)
    );

    videoFile = await ai.files.get({
      name: videoFile.name,
    });
  }

  if (videoFile.state === "FAILED") {
    throw new Error("Gemini failed to process the video.");
  }

  console.log("Gemini video is ready.");

  const prompt = `
You are ClipAI, an AI editor that finds viral short-form clips.

Analyze the entire video including:
- spoken words
- audio
- visual events
- emotions
- surprises
- storytelling
- useful information
- controversial or interesting statements
- strong hooks
- payoffs

Find the ${numberOfClips} BEST independent moments for:
YouTube Shorts, TikTok and Instagram Reels.

IMPORTANT TIMESTAMP RULES:

- Return exact timestamps from the video.
- Every clip must be 20 to 60 seconds.
- Do not invent timestamps.
- Do not make clips overlap.
- Start slightly before the important statement.
- End after the payoff.
- Avoid greetings and boring introductions.
- Avoid long silence.
- Prefer moments with strong retention potential.

Rank clips by viral potential.

Return ONLY this JSON:

{
  "clips": [
    {
      "start": 12.5,
      "end": 47.2,
      "score": 96,
      "title": "Short title",
      "reason": "Why this moment could perform well"
    }
  ]
}
`;

  console.log("Asking Gemini to find the best clips...");

  const response = await ai.models.generateContent({
    model: "gemini-2.5-flash",
    contents: [
      {
        fileData: {
          fileUri: videoFile.uri,
          mimeType: videoFile.mimeType,
        },
      },
      {
        text: prompt,
      },
    ],
    config: {
      temperature: 0.2,
      responseMimeType: "application/json",
    },
  });

  const text = response.text;

  if (!text) {
    throw new Error("Gemini returned an empty response.");
  }

  console.log("Gemini response received.");

  const data = extractJson(text);

  if (!Array.isArray(data.clips)) {
    throw new Error("Gemini did not return clips.");
  }

  return data.clips;
}

/* ================================= */
/* CREATE SHORT */
/* ================================= */

function createClip(
  input,
  output,
  start,
  duration,
  format
) {
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

    if (format === "9:16") {
      command = command.videoFilters(
        "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920"
      );
    }

    if (format === "1:1") {
      command = command.videoFilters(
        "scale=1080:1080:force_original_aspect_ratio=increase,crop=1080:1080"
      );
    }

    if (format === "16:9") {
      command = command.videoFilters(
        "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080"
      );
    }

    command
      .on("start", (commandLine) => {
        console.log("FFmpeg:", commandLine);
      })
      .on("end", resolve)
      .on("error", reject)
      .save(output);
  });
}

/* ================================= */
/* YOUTUBE DOWNLOAD */
/* ================================= */

async function downloadYouTube(url) {
  const parsed = new URL(url);

  const allowedHosts = [
    "youtube.com",
    "www.youtube.com",
    "youtu.be",
    "m.youtube.com",
  ];

  if (!allowedHosts.includes(parsed.hostname)) {
    throw new Error("Only YouTube URLs are supported.");
  }

  const base = path.join(
    uploadsDir,
    `youtube-${Date.now()}`
  );

  console.log("Downloading YouTube video...");

  await ytDlp(url, {
    output: `${base}.%(ext)s`,
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
      file.startsWith(path.basename(base))
    );

  if (!files.length) {
    throw new Error(
      "YouTube video could not be downloaded."
    );
  }

  return path.join(uploadsDir, files[0]);
}

/* ================================= */
/* MAIN ANALYZE ENDPOINT */
/* ================================= */

app.post(
  "/api/analyze",
  upload.single("video"),
  async (req, res) => {
    let videoPath = null;

    try {
      const url = String(
        req.body?.url || ""
      ).trim();

      const numberOfClips = Math.min(
        15,
        Math.max(
          1,
          parseInt(
            req.body?.numberOfClips || "5",
            10
          )
        )
      );

      const format =
        String(req.body?.format || "9:16");

      console.log("Analyze request received.");

      /* ----------------------------- */
      /* VIDEO SOURCE */
      /* ----------------------------- */

      if (req.file) {
        console.log("Using uploaded video.");
        videoPath = req.file.path;
      } else if (url) {
        console.log("Using YouTube URL.");
        videoPath = await downloadYouTube(url);
      } else {
        return res.status(400).json({
          error:
            "Upload a video or provide a YouTube URL.",
        });
      }

      /* ----------------------------- */
      /* DURATION */
      /* ----------------------------- */

      const duration =
        await getVideoDuration(videoPath);

      console.log(
        `Video duration: ${duration.toFixed(2)} seconds`
      );

      /* ----------------------------- */
      /* GEMINI */
      /* ----------------------------- */

      const aiClips =
        await analyzeVideoWithGemini(
          videoPath,
          numberOfClips
        );

      const clips = aiClips
        .map((clip) => ({
          start: Math.max(
            0,
            Number(clip.start)
          ),
          end: Math.min(
            duration,
            Number(clip.end)
          ),
          score: Number(
            clip.score || 0
          ),
          title:
            String(
              clip.title || "Clip"
            ),
          reason:
            String(
              clip.reason || ""
            ),
        }))
        .filter((clip) => {
          const length =
            clip.end - clip.start;

          return (
            clip.end > clip.start &&
            length >= 20 &&
            length <= 60
          );
        })
        .sort(
          (a, b) =>
            b.score - a.score
        )
        .slice(
          0,
          numberOfClips
        );

      if (!clips.length) {
        throw new Error(
          "Gemini could not find suitable clips."
        );
      }

      /* ----------------------------- */
      /* RENDER CLIPS */
      /* ----------------------------- */

      const results = [];

      for (
        let i = 0;
        i < clips.length;
        i++
      ) {
        const clip = clips[i];

        const outputName =
          `clip-${Date.now()}-${i + 1}.mp4`;

        const outputPath =
          path.join(
            outputsDir,
            outputName
          );

        console.log(
          `Rendering clip ${i + 1}/${clips.length}`
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

      console.log(
        `Finished ${results.length} clips.`
      );

      return res.json({
        success: true,
        ai: "Gemini",
        duration,
        clips: results,
      });
    } catch (error) {
      console.error(
        "ANALYZE ERROR:",
        error
      );

      return res.status(500).json({
        error:
          error?.message ||
          "Server error",
      });
    } finally {
      cleanup(videoPath);
    }
  }
);

app.listen(PORT, () => {
  console.log(
    `ClipAI server running on port ${PORT}`
  );
});
