import express from "express";
import cors from "cors";
import multer from "multer";
import OpenAI from "openai";
import ffmpeg from "fluent-ffmpeg";
import ffmpegPath from "ffmpeg-static";
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

app.get("/", (req, res) => {
  res.json({
    status: "ok",
    message: "ClipAI server is running"
  });
});

app.post("/api/analyze", upload.single("video"), async (req, res) => {
  let videoPath = null;
  let audioPath = null;

  try {
    if (!process.env.OPENAI_API_KEY) {
      return res.status(500).json({
        error: "OPENAI_API_KEY is not configured"
      });
    }

    if (!req.file) {
      return res.status(400).json({
        error: "Video file is required"
      });
    }

    videoPath = req.file.path;

    audioPath = path.join(
      uploadDir,
      `${req.file.filename}.mp3`
    );

    console.log("Extracting audio...");

    await extractAudio(videoPath, audioPath);

    console.log("Transcribing video...");

    const transcription =
      await openai.audio.transcriptions.create({
        file: fs.createReadStream(audioPath),
        model: "gpt-transcribe",
        response_format: "verbose_json",
        timestamp_granularities: ["segment"]
      });

    const segments = (transcription.segments || []).map(
      (segment) => ({
        start: Number(segment.start),
        end: Number(segment.end),
        text: segment.text.trim()
      })
    );

    if (!segments.length) {
      throw new Error(
        "No speech segments were detected"
      );
    }

    console.log(
      `Found ${segments.length} transcript segments`
    );

    const numberOfClips =
      Number(req.body.numberOfClips || 5);

    const transcriptForAI = segments
      .map(
        (s, i) =>
          `[${i}] ${s.start.toFixed(2)}-${s.end.toFixed(2)}: ${s.text}`
      )
      .join("\n");

    console.log(
      "AI is selecting the best moments..."
    );

    const aiResponse =
      await openai.responses.create({
        model: "gpt-5.6",
        input: [
          {
            role: "system",
            content: `
You are an expert short-form video editor.

Find the most viral and engaging moments
from the supplied transcript.

Look for:

- strong hooks
- surprising statements
- curiosity
- emotion
- useful information
- controversial statements
- interesting stories
- strong payoffs

Avoid:

- greetings
- introductions without value
- filler
- long pauses
- repetitive content
- incomplete thoughts

Each clip should normally be
20 to 60 seconds long.

Start slightly before the hook
when necessary.

End after the payoff.

Never invent timestamps.

Use only timestamps available
in the transcript.

Clips must not overlap.

Return the best clips first.
`
          },
          {
            role: "user",
            content: `
Find the ${numberOfClips} best clips.

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
              required: ["clips"],
              additionalProperties: false
            }
          }
        }
      });

    const result =
      JSON.parse(aiResponse.output_text);

    console.log(
      `AI selected ${result.clips.length} clips`
    );

    const clips = [];

    for (
      let i = 0;
      i < result.clips.length;
      i++
    ) {
      const clip = result.clips[i];

      const start = Math.max(
        0,
        Number(clip.start)
      );

      const end = Number(clip.end);

      if (
        !Number.isFinite(start) ||
        !Number.isFinite(end) ||
        end <= start ||
        end - start < 5
      ) {
        continue;
      }

      const outputFile = path.join(
        outputDir,
        `${req.file.filename}-clip-${i + 1}.mp4`
      );

      await createClip(
        videoPath,
        outputFile,
        start,
        end - start
      );

      clips.push({
        id: i + 1,
        title: clip.title,
        score: clip.score,
        reason: clip.reason,
        start,
        end,
        url:
          `/outputs/${path.basename(outputFile)}`
      });
    }

    res.json({
      success: true,
      transcript: transcription.text,
      clips
    });

  } catch (error) {

    console.error(error);

    res.status(500).json({
      success: false,
      error:
        error.message ||
        "Video processing failed"
    });

  } finally {

    if (
      audioPath &&
      fs.existsSync(audioPath)
    ) {
      fs.unlinkSync(audioPath);
    }

    if (
      videoPath &&
      fs.existsSync(videoPath)
    ) {
      fs.unlinkSync(videoPath);
    }
  }
});

app.use(
  "/outputs",
  express.static(outputDir)
);

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

function extractAudio(
  video,
  audio
) {
  return new Promise(
    (resolve, reject) => {

      ffmpeg(video)
        .noVideo()
        .audioCodec("libmp3lame")
        .audioFrequency(16000)
        .audioChannels(1)
        .format("mp3")
        .on("end", resolve)
        .on("error", reject)
        .save(audio);

    }
  );
}

function createClip(
  video,
  output,
  start,
  duration
) {
  return new Promise(
    (resolve, reject) => {

      ffmpeg(video)
        .setStartTime(start)
        .setDuration(duration)
        .videoCodec("libx264")
        .audioCodec("aac")
        .outputOptions([
          "-preset",
          "veryfast",
          "-crf",
          "23",
          "-movflags",
          "+faststart"
        ])
        .on("end", resolve)
        .on("error", reject)
        .save(output);

    }
  );
            }
