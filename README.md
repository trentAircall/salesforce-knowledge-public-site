# Salesforce Knowledge Public Site

Expose published Salesforce Knowledge articles as clean, semantic HTML pages
suitable for crawling by AI knowledge-base ingestion tools, voice agents, or
any external system that needs read-only access to your knowledge content.

## The story

A Salesforce-heavy customer was setting up an AI voice agent and needed to
feed it a knowledge base. They were already publishing store information
(addresses, opening hours, etc.) on their public website, sourced from
Salesforce Knowledge articles. To get the same content into the voice agent,
their Salesforce admin took a sensible-looking shortcut: they spun up a
public Apex REST endpoint that returned the relevant Knowledge article
straight out of the database — XML on the outside, with the rich-text article
body sitting inside as a string of HTML.

You can see what that looks like in [`examples/before.xml`](examples/before.xml).
Functionally it works — the article content is there, in full. But there are
problems for any consumer that isn't another internal system:

1. **Web crawlers expect a web page.** Most modern AI ingestion tools use
   Readability-style heuristics to identify "main content" and discard
   boilerplate. Handed an XML response, the crawler has no `<title>`, no
   `<meta>`, no `<main>`, no semantic structure to lock onto. It often gives
   up or extracts something inconsistent.
2. **The article body is a single HTML table.** Tables compress information
   well visually but read terribly when chunked by a retrieval system or
   spoken aloud by a voice agent. "Row 1, column 2: 100 Main St" is not how
   anyone wants to hear an answer to "where's your nearest store?"
3. **It's tied to one article.** The endpoint hard-codes a specific article
   and returns it raw. There's no index, no sitemap, no way to discover and
   ingest the broader knowledge base as it grows.

This project is the answer. It exposes the same underlying Salesforce
Knowledge content via a tiny Force.com Site, but produces a clean, crawler-
and voice-friendly HTML page per article. Tables become prose sections with
semantic markup. The output looks like
[`examples/after.html`](examples/after.html) — small, structured, and
trivially consumable by any system.

The result is a thin dynamic surface that any external system can consume —
and which updates the moment the underlying Knowledge article is republished.

## Why this exists

Salesforce Knowledge is the right place to author and govern customer-facing
content — but the standard public surface (Public Knowledge Base on Experience
Cloud) is heavy, opinionated, and produces output that web crawlers and AI
tools struggle to parse cleanly.

This project exposes a minimal Force.com Site endpoint that:

- Lists all articles flagged **Public Knowledge Base** as a simple HTML index
- Renders each article from its rich-text body field as semantic HTML
- Sanitises the noisy output of the Lightning rich-text editor
- Converts tables into prose-style sections that read naturally aloud
  (voice-agent friendly) and chunk well for retrieval (crawler friendly)
- Emits a `sitemap.xml` so crawlers can discover every article

The result is a tiny, dynamic surface that any system can consume — and which
updates the moment the underlying Knowledge article is republished.

## Endpoints

Relative to your site's `/services/apexrest/AircallKB/` path:

| Path             | Returns                                         |
| ---------------- | ----------------------------------------------- |
| `/`              | HTML index of all published, public articles    |
| `/<UrlName>`     | One article rendered as clean semantic HTML     |
| `/sitemap.xml`   | XML sitemap listing all article URLs            |

## What the parser handles

The Apex class (`AircallKBController`) sanitises and normalises the rich-text
output of the Salesforce Lightning editor:

- Strips inline `style`, `class`, `id`, `data-*` and other presentational attributes
- Unwraps `<font>` and `<span>` (both used for color/font choices)
- Maps `<b>`→`<strong>`, `<i>`→`<em>`, `<strike>`→`<s>`, `<div>`→`<p>`
- Removes images (Salesforce internal `src` URLs don't resolve for guest users)
- Collapses Quill's empty-line markers (`<p><br></p>`, `<p>&nbsp;</p>`)
- Strips Microsoft Word conditional comments left behind by paste
- Defensively removes `<script>`, `<iframe>`, `<style>`, etc. (Salesforce
  already does this server-side; belt-and-braces only)

For tables, each row becomes a `<section>` with the first column as `<h2>`
and remaining columns rendered as prose paragraphs:

> **Downtown Branch**
> The address is 100 Main St, Sydney NSW 2000.
> The opening hours are Mon–Sun: 10am–11pm.

This is dynamic — add a `Phone Number` column to the article table and the
output gains "The phone number is..." paragraphs with no Apex change.

## Getting started

A full step-by-step UI walkthrough is in
**[`docs/IMPLEMENTATION.md`](docs/IMPLEMENTATION.md)** — covering Knowledge
enablement, creating the body field, deploying the Apex, creating the public
site, configuring guest permissions, publishing your first article, and
testing the endpoint.

For developers who prefer the CLI:

```bash
sf org login web --alias myorg
sf project deploy start --target-org myorg
```

## Configuration

Open `force-app/main/default/classes/AircallKBController.cls` and adjust the
three constants at the top:

```apex
private static final String BODY_FIELD = 'Answer__c';
private static final String LANGUAGE   = 'en_US';
private static final String PUBLIC_BASE_URL = 'https://....my.salesforce-sites.com/kb/services/apexrest/AircallKB/';
```

- `BODY_FIELD` — the API name of the rich-text field on `Knowledge__kav` that
  contains your article body. Salesforce Knowledge ships without a body field
  by default — admins typically create their own (commonly `Answer__c`).
- `LANGUAGE` — the language code to publish (matches your default Knowledge
  language).
- `PUBLIC_BASE_URL` — the base URL of your Force.com Site, used in the
  sitemap. Must end with `/services/apexrest/AircallKB/`.

## Setup checklist

In your Salesforce org:

1. **Enable Lightning Knowledge** (Setup → Knowledge Settings)
2. **Create your body field** (custom rich-text field on `Knowledge__kav`,
   referenced by `BODY_FIELD` above)
3. **Create a Force.com Site** (Setup → Sites — *not* Experience Cloud; the
   classic Force.com Site allows unauthenticated REST access)
4. **Grant the site's guest profile** the following:
   - Apex Class Access for `AircallKBController`
   - Read access to `Knowledge__kav`
   - Read FLS on the body field (`Answer__c` or whatever you've named it)
5. **Author and publish your articles**, ticking the **Public Knowledge Base**
   channel so they appear on the public site

## Production hardening

For production use, consider:

- Switching to authenticated access (OAuth via a Connected App + dedicated
  integration user on a Salesforce Integration license)
- Adding test classes for the controller (deploy will require coverage to
  production orgs)
- Reviewing the language filter if you publish in multiple languages

## License

MIT
