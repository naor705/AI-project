"""
Market Research Analyst Agent — Beauty Niche
Generates viral content ideas and engagement strategies.
Product is optional; content is always produced.
"""

import anthropic
import json
import sys
import argparse


SYSTEM_PROMPT = """You are a Market Research Analyst Agent specialized in the beauty niche.
Your focus is maximizing user engagement and creating viral content.

When a product is provided, tailor all output to highlight that product.
When no product is provided, generate niche-level beauty content that works for any brand or creator.

Always return ONLY valid JSON matching the required schema — no extra text, no markdown fences."""

def build_user_prompt(product_name: str | None, goal: str) -> str:
    if product_name:
        product_context = f'The product is: "{product_name}". Tailor all queries, hooks, and ideas around it.'
        placeholder_note = f'Use "{product_name}" wherever a product name fits naturally.'
    else:
        product_context = "No specific product has been provided."
        placeholder_note = (
            "Generate niche-level beauty content. Where a product name would fit, "
            'use the placeholder "{product}" so it stays interchangeable.'
        )

    return f"""Generate a market research report for the beauty niche.

Goal: {goal}
{product_context}
{placeholder_note}

Return a JSON object with exactly this schema:
{{
  "product": "<product name or null>",
  "queries": ["<5 search queries>"],
  "urls": ["<3 URLs to scrape for insights>"],
  "trends": "<paragraph describing current beauty trends>",
  "content_patterns": "<paragraph describing what content formats drive high engagement>",
  "ideas": [
    {{
      "title": "<content idea title>",
      "format": "<platform and format e.g. TikTok 30s video>",
      "hook": "<opening line or visual hook>",
      "why_it_works": "<engagement reasoning>"
    }}
  ]
}}

Rules:
- queries: exactly 5 items
- urls: exactly 3 items
- ideas: exactly 3 items
- Return ONLY the JSON object, nothing else"""


def run_agent(product_name: str | None = None, goal: str = "user engagement and viral content") -> dict:
    client = anthropic.Anthropic()

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=2048,
        system=SYSTEM_PROMPT,
        messages=[
            {"role": "user", "content": build_user_prompt(product_name, goal)}
        ],
    )

    raw = message.content[0].text.strip()

    # Strip markdown fences if model wraps output despite instructions
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
        raw = raw.strip()

    result = json.loads(raw)
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Beauty niche market research agent — product is optional"
    )
    parser.add_argument(
        "--product",
        type=str,
        default=None,
        help="Product name to focus on (optional). Omit for niche-level content.",
    )
    parser.add_argument(
        "--goal",
        type=str,
        default="user engagement and viral content",
        help='Research goal (default: "user engagement and viral content")',
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print the JSON output",
    )
    args = parser.parse_args()

    result = run_agent(product_name=args.product, goal=args.goal)

    indent = 2 if args.pretty else None
    print(json.dumps(result, indent=indent))


if __name__ == "__main__":
    main()
