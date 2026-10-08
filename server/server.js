import express from "express";
import cors from "cors";
import multer from "multer";
import OpenAI from "openai";
import ffmpeg from "fluent-ffmpeg";
import ffmpegPath from "ffmpeg-static";
import ytDlp from "yt-dlp-exec";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

ffmpeg.setFfmpegPath(ffmpegPath);

const app = express();

app.use(cors());
app.use(express.json());

const uploadDir = path.join(__dirname, "uploads");
const outputDir = path.join(__dirname, "outputs");

fs.mkdirSync(uploadDir, { recursive: true });
fs.mkdirSync(outputDir, { recursive: true });

const upload = multer({
  dest: uploadDir,
  limits: {
    fileSize: 500 * 1024 * 1024
  }
});

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

/* =========================
   HOME
========================= */

app.get("/", (req, res) => {
  res.json({
    status: "ok",
    message: "ClipAI server is running"
  });
});

/* =========================
   ANALYZE
========================= */

app.post(
  "/api/analyze",
  upload.single("video"),
  async (req, res) => {

    let videoPath = null;
    let audioPath = null;
    let downloadedFromUrl = false;

    try {

      if (!process.env.OPENAI_API_KEY) {
        return res.status(500).json({
          error: "OPENAI_API_KEY is not configured"
        });
      }

      const videoUrl =
        typeof req.body?.url === "string"
          ? req.body.url.trim()
          : "";

      /* =========================
         GET VIDEO
      ========================= */

      if (req.file) {

        console.log("Using uploaded video");

        videoPath = req.file.path;

      } else if (videoUrl) {

        console.log("Video URL received");

        if (!isAllowedVideoUrl(videoUrl)) {
          return res.status(400).json({
            error:
              "Only supported video URLs are allowed."
          });
        }

        const downloadedPath =
          await downloadVideo(videoUrl);

        videoPath = downloadedPath;
        downloadedFromUrl = true;

      } else {

        return res.status(400).json({
          error:
            "Upload a video or provide a video URL."
        });
      }

      /* =========================
         EXTRACT AUDIO
      ========================= */

      audioPath = path.join(
        uploadDir,
        `audio-${Date.now()}.mp3`
      );

      console.log("Extracting audio...");

      await extractAudio(
        videoPath,
        audioPath
      );

      /* =========================
         TRANSCRIPTION
      ========================= */

      console.log("Transcribing video...");

      const transcription =
        await openai.audio.transcriptions.create({
          file: fs.createReadStream(audioPath),
          model: "gpt-transcribe",
          response_format: "verbose_json",
          timestamp_granularities: ["segment"]
        });

      const segments =
        (transcription.segments || [])
          .map((segment) => ({
            start: Number(segment.start),
            end: Number(segment.end),
            text: String(segment.text || "").trim()
          }))
          .filter(
            (segment) =>
              Number.isFinite(segment.start) &&
              Number.isFinite(segment.end) &&
              segment.end > segment.start &&
              segment.text.length > 0
          );

      if (!segments.length) {
        throw new Error(
          "No speech segments were detected."
        );
      }

      console.log(
        `Found ${segments.length} transcript segments`
      );

      /* =========================
         NUMBER OF CLIPS
      ========================= */

      let numberOfClips =
        Number(req.body?.numberOfClips || 5);

      if (
        !Number.isFinite(numberOfClips) ||
        numberOfClips < 1
      ) {
        numberOfClips = 5;
      }

      numberOfClips =
        Math.min(numberOfClips, 15);

      /* =========================
         TRANSCRIPT FOR AI
      ========================= */

      const transcriptForAI =
        segments
          .map(
            (s, i) =>
              `[${i}] ${s.start.toFixed(2)}-${s.end.toFixed(2)}: ${s.text}`
          )
          .join("\n");

      console.log(
        "AI is selecting the best moments..."
      );

      /* =========================
         AI CLIP SELECTION
      ========================= */

      const aiResponse =
        await openai.responses.create({

          model: "gpt-5.6-sol",

          input: [

            {
              role: "system",

              content: `
You are an expert short-form video editor.

Your job is to find the strongest moments
from a long-form video transcript.

Choose moments that have high potential
for Shorts/Reels/TikTok.

Look for:

- extremely strong hooks
- surprising statements
- emotional moments
- useful information
- curiosity
- controversy
- storytelling
- unexpected facts
- strong opinions
- funny moments
- strong payoffs
- moments that make viewers want to keep watching

Avoid:

- greetings
- introductions without value
- filler
- repetitive statements
- long explanations without a payoff
- incomplete thoughts
- moments that need missing context

Each clip should normally be
20-60 seconds.

A clip may be slightly shorter or longer
if necessary for a complete thought.

Start slightly before the important statement
when necessary.

End after the payoff.

Use ONLY timestamps contained
in the transcript.

NEVER invent timestamps.

Clips must not overlap.

Return the strongest clips first.

Score each clip from 0 to 100.
`
            },

            {
              role: "user",

              content: `
Find the ${numberOfClips} strongest clips.

TRANSCRIPT:

${transcriptForAI}
`
            }
          ],

          text: {
            format: {
              type: "json_schema",

              name: "clip_selection",

              strict: true,

              schema: {

                type: "object",

                properties: {

                  clips: {

                    type: "array",

                    items: {

                      type: "object",

                      properties: {

                        start: {
                          type: "number"
                        },

                        end: {
                          type: "number"
                        },

                        title: {
                          type: "string"
                        },

                        score: {
                          type: "number"
                        },

                        reason: {
                          type: "string"
                        }

                      },

                      required: [
                        "start",
                        "end",
                        "title",
                        "score",
                        "reason"
                      ],

                      additionalProperties: false
                    }
                  }
                },

                required: [
                  "clips"
                ],

                additionalProperties: false
              }
            }
          }
        });

      const result =
        JSON.parse(
          aiResponse.output_text
        );

      console.log(
        `AI selected ${result.clips.length} clips`
      );

      /* =========================
         CREATE CLIPS
      ========================= */

      const clips = [];

      for (
        let i = 0;
        i < result.clips.length;
        i++
      ) {

        const clip = result.clips[i];

        const start =
          Math.max(
            0,
            Number(clip.start)
          );

        const end =
          Number(clip.end);

        if (
          !Number.isFinite(start) ||
          !Number.isFinite(end) ||
          end <= start ||
          end - start < 5
        ) {
          continue;
        }

        const duration =
          end - start;

        const outputFile =
          path.join(
            outputDir,
            `${Date.now()}-clip-${i + 1}.mp4`
          );

        console.log(
          `Creating clip ${i + 1}: ${start}s - ${end}s`
        );

        await createClip(
          videoPath,
          outputFile,
          start,
          duration
        );

        clips.push({

          id: i + 1,

          title:
            clip.title ||
            `Best Moment ${i + 1}`,

          score:
            Number(clip.score) || 0,

          reason:
            clip.reason || "",

          start,

          end,

          url:
            `/outputs/${path.basename(
              outputFile
            )}`
        });
      }

      /* =========================
         RESPONSE
      ========================= */

      res.json({

        success: true,

        transcript:
          transcription.text || "",

        clips
      });

    } catch (error) {

      console.error(
        "ANALYZE ERROR:",
        error
      );

      res.status(500).json({

        success: false,

        error:
          error?.message ||
          "Video processing failed."
      });

    } finally {

      /* =========================
         CLEAN TEMP FILES
      ========================= */

      if (
        audioPath &&
        fs.existsSync(audioPath)
      ) {

        try {
          fs.unlinkSync(audioPath);
        } catch (_) {}

      }

      if (
        videoPath &&
        downloadedFromUrl &&
        fs.existsSync(videoPath)
      ) {

        try {
          fs.unlinkSync(videoPath);
        } catch (_) {}

      }

      if (
        videoPath &&
        req.file &&
        fs.existsSync(videoPath)
      ) {

        try {
          fs.unlinkSync(videoPath);
        } catch (_) {}

      }
    }
  }
);

/* =========================
   OUTPUTS
========================= */

app.use(
  "/outputs",
  express.static(outputDir)
);

/* =========================
   SERVER
========================= */

const PORT =
  process.env.PORT || 3000;

app.listen(
  PORT,
  "0.0.0.0",
  () => {

    console.log(
      `ClipAI server running on port ${PORT}`
    );

  }
);

/* =========================
   URL VALIDATION
========================= */

function isAllowedVideoUrl(url) {

  try {

    const parsed =
      new URL(url);

    const hostname =
      parsed.hostname
        .toLowerCase()
        .replace(/^www\./, "");

    return (
      hostname === "youtube.com" ||
      hostname === "youtu.be" ||
      hostname === "m.youtube.com"
    );

  } catch (_) {

    return false;

  }
}

/* =========================
   DOWNLOAD VIDEO FROM URL
========================= */

async function downloadVideo(url) {

  const id =
    `download-${Date.now()}`;

  const outputTemplate =
    path.join(
      uploadDir,
      `${id}.%(ext)s`
    );

  console.log(
    "Downloading authorized video..."
  );

  await ytDlp(
    url,
    {

      output:
        outputTemplate,

      format:
        "best[height<=720]/best",

      mergeOutputFormat:
        "mp4",

      noPlaylist:
        true,

      noWarnings:
        true,

      quiet:
        true,

      restrictFilenames:
        true,

      ffmpegLocation:
        path.dirname(ffmpegPath)

    }
  );

  const files =
    fs.readdirSync(uploadDir);

  const downloaded =
    files.find(
      (file) =>
        file.startsWith(`${id}.`)
    );

  if (!downloaded) {

    throw new Error(
      "Could not download the video."
    );

  }

  const downloadedPath =
    path.join(
      uploadDir,
      downloaded
    );

  console.log(
    `Video downloaded: ${downloadedPath}`
  );

  return downloadedPath;
}

/* =========================
   EXTRACT AUDIO
========================= */

function extractAudio(
  video,
  audio
) {

  return new Promise(
    (resolve, reject) => {

      ffmpeg(video)

        .noVideo()

        .audioCodec(
          "libmp3lame"
        )

        .audioFrequency(
          16000
        )

        .audioChannels(
          1
        )

        .format("mp3")

        .on(
          "end",
          resolve
        )

        .on(
          "error",
          reject
        )

        .save(audio);

    }
  );
}

/* =========================
   CREATE CLIP
========================= */

function createClip(
  video,
  output,
  start,
  duration
) {

  return new Promise(
    (resolve, reject) => {

      ffmpeg(video)

        .setStartTime(
          start
        )

        .setDuration(
          duration
        )

        .videoCodec(
          "libx264"
        )

        .audioCodec(
          "aac"
        )

        .outputOptions([

          "-preset",
          "veryfast",

          "-crf",
          "23",

          "-movflags",
          "+faststart"

        ])

        .on(
          "end",
          resolve
        )

        .on(
          "error",
          reject
        )

        .save(output);

    }
  );
}
