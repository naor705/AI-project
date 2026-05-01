# Short-Form Video Automation MVP

An n8n workflow that automatically turns TikTok trend data into original short-form videos — scored, scripted by AI, rendered by Creatomate, approved via Telegram, and published through Upload-Post.

> **Content policy:** This workflow fetches TikTok trend *metadata only*. No original videos are downloaded or reuploaded. All generated content is original, created by AI and your own Creatomate template.

---

## Workflow Overview

```
Manual / Schedule Trigger
  → Fetch TikTok Trends (Apify)     ← metadata only, no video download
  → Calculate Engagement Score       ← top trend selected
  → Build OpenAI Request             ← AI prompt: "create original content"
  → AI Creates Video Idea (OpenAI)   ← structured JSON concept
  → Parse AI Response
  → Build Creatomate Request
  → Generate Video (Creatomate)      ← 9:16 vertical video rendered
  → Extract Render ID
  → Wait 60s
  → Check Render Status
  → Is Render Complete?
      ├─ YES → Build Telegram Message
      │         → Send Video to Telegram
      │         → Wait for Approval (Webhook)
      │         → Check Approval
      │             ├─ APPROVED → Build Upload-Post Request
      │             │              → Publish with Upload-Post
      │             │              → Build Sheets Log Row
      │             │              → Log to Google Sheets
      │             └─ REJECTED → Log Rejection
      └─ NO  → Stop - Render Failed
```

---

## Required Accounts

| Service | Purpose | Free Tier |
|---|---|---|
| [Apify](https://apify.com) | TikTok trend scraping | Yes (limited) |
| [OpenAI](https://platform.openai.com) | AI video concept generation | Pay-per-use |
| [Creatomate](https://creatomate.com) | Video rendering from templates | Yes (watermarked) |
| [Telegram](https://telegram.org) | Approval notifications | Free |
| [Upload-Post](https://upload-post.com) | TikTok publishing | Paid |
| [Google Sheets](https://sheets.google.com) | Run logging | Free |
| [n8n](https://n8n.io) | Workflow automation | Self-host free / Cloud paid |

---

## Required API Keys

Copy `.env.example` to `.env` for local reference. In n8n, set these in **Settings → Environment Variables**.

### Apify
1. Sign up at [apify.com](https://apify.com)
2. Go to **Settings → Integrations → API token**
3. Copy token → `APIFY_API_TOKEN`
4. Find a TikTok scraper actor (e.g. search "TikTok" in [Apify Store](https://apify.com/store))
   - Recommended: `clockworks/tiktok-hashtag-search` or `clockworks/free-tiktok-scraper`
5. Copy the actor ID → `APIFY_ACTOR_ID` (e.g. `clockworks~tiktok-hashtag-search`)

### OpenAI
1. Sign up at [platform.openai.com](https://platform.openai.com)
2. Go to **API keys → Create new secret key**
3. Copy key → `OPENAI_API_KEY`

### Creatomate
1. Sign up at [creatomate.com](https://creatomate.com)
2. Go to **Settings → API** → copy key → `CREATOMATE_API_KEY`
3. Create a vertical (9:16, 1080×1920) template with the elements listed below
4. Copy the template ID → `CREATOMATE_TEMPLATE_ID`

### Telegram
1. Open Telegram and message **@BotFather**
2. Send `/newbot` and follow prompts
3. Copy the bot token → `TELEGRAM_BOT_TOKEN`
4. Add your bot to your group or use the direct chat
5. Get your chat ID:
   - Forward a message from the chat to [@userinfobot](https://t.me/userinfobot)
   - Or call: `https://api.telegram.org/bot<TOKEN>/getUpdates`
6. Copy chat ID → `TELEGRAM_CHAT_ID` (groups are negative numbers, e.g. `-1001234567890`)

### Upload-Post
1. Sign up at [upload-post.com](https://upload-post.com)
2. Go to **API settings** → copy key → `UPLOAD_POST_API_KEY`
3. Copy your account/workspace ID → `UPLOAD_POST_ACCOUNT_ID`
4. Verify the exact API endpoint in their docs — the workflow uses `https://www.upload-post.com/api/upload`

### Google Sheets
1. Create a new Google Sheet
2. Add this header row (row 1, columns A→K):
   ```
   date | trend_url | engagement_score | generated_video_url | caption |
   product_category | approval_status | publish_status | publish_url |
   video_title | products
   ```
3. Copy the sheet ID from the URL (the long string between `/d/` and `/edit`) → `GOOGLE_SHEET_ID`
4. For the access token, choose one option:
   - **Option A (Simple):** Replace the Log to Google Sheets node with the native **Google Sheets** n8n node and configure Google OAuth2 credentials in n8n — this handles token refresh automatically
   - **Option B (API):** Create a Google Cloud service account, share the sheet with it, generate a key, and use the access token → `GOOGLE_SHEETS_ACCESS_TOKEN`

---

## Required n8n Credentials

The workflow uses environment variables rather than n8n's credential store for maximum portability. No n8n credentials need to be configured unless you swap the Google Sheets HTTP Request node for the native Google Sheets node.

---

## How to Import the Workflow

1. Open your n8n instance
2. Go to **Workflows → Import from file**
3. Select `n8n-workflow.json`
4. Click **Import**
5. The workflow will appear with all nodes pre-configured
6. Set all environment variables (see above)
7. The workflow starts **inactive** — test manually before activating

---

## How to Test Manually

1. Ensure all environment variables are set in n8n
2. Open the imported workflow
3. Click **Manual Trigger** node → **Test step** (or click the triangle "Execute" button)
4. Watch each node execute in sequence
5. When execution reaches **Wait for Approval**, it pauses
6. Check Telegram — you should receive a message with Approve/Reject links
7. Click Approve to continue; the workflow publishes and logs
8. Check your Google Sheet for the new log row

**Tip:** To test individual nodes, click any node and use "Execute this node" after running up to that point.

---

## How to Switch to Schedule Trigger

1. Disable (or ignore) the Manual Trigger — it only fires when you click it manually
2. Click the **Schedule Trigger (Daily 9AM)** node to configure the schedule
3. The default cron `0 9 * * *` runs daily at 9:00 AM server time
4. Common alternatives:
   - `0 8 * * 1-5` — weekdays at 8 AM
   - `0 9,18 * * *` — twice daily at 9 AM and 6 PM
   - `0 9 * * 1` — every Monday at 9 AM
5. Click **Activate** (top-right toggle) to enable the schedule

---

## How to Connect Telegram Approval

The approval flow uses n8n's **Wait node in webhook mode**:

1. When the workflow reaches "Wait for Approval (Webhook)", it pauses and generates a unique resume URL
2. This URL is automatically included in the Telegram message as Approve/Reject links
3. Clicking either link calls the URL with `?approved=true` or `?approved=false`
4. n8n resumes the workflow with that query parameter
5. The "Check Approval" IF node routes based on the value

**Troubleshooting:**
- If Telegram links don't work, ensure your n8n instance is publicly accessible (not localhost)
- For self-hosted n8n, set `N8N_WEBHOOK_URL` in your n8n environment to your public URL
- The resume URL expires if n8n restarts — approve/reject before restarting n8n

---

## How to Connect Creatomate Template Fields

The "Build Creatomate Request" Code node maps AI output to your template. Edit that node to match your template's element names exactly.

**Default mapping (change the left side to match your template):**

```javascript
'video_title'      → idea.video_title
'scene_1_text'     → idea.scene_descriptions[0]
'scene_2_text'     → idea.scene_descriptions[1]
'scene_3_text'     → idea.scene_descriptions[2]
'on_screen_text_1' → idea.on_screen_text[0]
'on_screen_text_2' → idea.on_screen_text[1]
'product_category' → idea.product_category
'product_name'     → idea.suggested_products[0]
'cta_text'         → 'Shop Now 🛍️' (static)
'voiceover'        → idea.voiceover_script
```

**To add/change elements:**
1. Open "Build Creatomate Request" Code node
2. Find the `modifications` object
3. Add/rename keys to match your template element names
4. Save and re-run

---

## How to Connect Upload-Post Publishing

1. Verify the API endpoint in Upload-Post's documentation — update the URL in the "Publish with Upload-Post" HTTP Request node if needed
2. The "Build Upload-Post Request" Code node builds the payload:
   - `platforms: ['tiktok']` — add `'instagram'`, `'facebook'`, `'youtube'` when ready
   - `caption` — AI-generated caption + hashtags combined
   - `video_url` — direct URL from Creatomate render
3. Check Upload-Post's docs for any additional required fields (e.g. `title`, `thumbnail_url`)

---

## Creatomate Template Setup (Step-by-Step)

1. Log in to [creatomate.com](https://creatomate.com) and click **New template**
2. Choose **Blank** → set dimensions to **1080 × 1920** (9:16 portrait)
3. Add these elements with these exact names:

   | Element | Type | Suggested Style |
   |---|---|---|
   | `video_title` | Text | Large, bold, top-third |
   | `scene_1_text` | Text | Medium, center |
   | `scene_2_text` | Text | Medium, center |
   | `scene_3_text` | Text | Medium, center |
   | `on_screen_text_1` | Text | Caption, lower third |
   | `on_screen_text_2` | Text | Caption, lower third |
   | `product_category` | Text | Tag/badge style |
   | `product_name` | Text | Highlight text |
   | `cta_text` | Text | Button overlay |
   | `voiceover` | Audio | Text-to-speech or file |

4. Add background media placeholders (images or video clips)
5. Click **Publish** → copy the template ID → `CREATOMATE_TEMPLATE_ID`

---

## Known Limitations

| Limitation | Notes |
|---|---|
| Single render poll | Waits 60s then checks once. Long renders will fail. Add a retry loop for production. |
| Apify actor variability | Different TikTok actors return different field names. The engagement node normalises the most common ones — adjust if your actor uses others. |
| Google Sheets token expiry | The HTTP-based Sheets logging uses a static access token. Switch to the native Google Sheets n8n node for automatic token refresh. |
| No retry on API errors | HTTP errors stop the workflow. Add `continueOnFail: true` and error-check nodes for production resilience. |
| Approval URL requires public n8n | The Telegram approve/reject links only work if your n8n webhook URL is publicly accessible. |
| Upload-Post API | Endpoint URL and payload format may vary by Upload-Post plan/version. Verify in their docs. |
| TikTok ToS | Always review TikTok's terms before publishing AI-generated content. Content policies change. |
| One trend per run | The MVP picks only the top-scored trend. Extend the engagement node to return the top N trends and run parallel branches. |

---

## File Reference

```
n8n-workflow.json   — Import this into n8n
README.md           — This file
.env.example        — Environment variable reference
```
