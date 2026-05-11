# Implementation Guide

A step-by-step walkthrough for setting this up in your Salesforce org using
only the Salesforce UI. No CLI or developer tools required.

By the end of this guide you'll have:

- Salesforce Knowledge enabled
- A custom rich-text body field on your Knowledge articles
- The Apex controller deployed
- A public Force.com Site exposing the endpoint
- Your first article authored, published, and visible at a public URL

---

## Step 1 — Enable Lightning Knowledge

If your org doesn't have Knowledge enabled yet:

1. **Setup → Knowledge Settings**
2. Click **Edit**
3. Tick **Yes, I understand the impact of enabling Lightning Knowledge**
4. **Save**

Then assign yourself the Knowledge User permission:

1. **Setup → Users** → click your user
2. **Edit** → tick **Knowledge User**
3. **Save**

---

## Step 2 — Create the body field on Knowledge

Salesforce Knowledge ships **without a body field by default** — every org
adds its own. The most common pattern is to create a custom rich-text field
called `Answer__c`, which is what this project assumes out of the box.

1. **Setup → Object Manager → Knowledge**
2. **Fields & Relationships → New**
3. Choose **Text Area (Rich)**
4. Field Label: `Answer`
   Field Name: `Answer` (Salesforce will create the API name `Answer__c`)
5. Length: `32,768`, Visible Lines: `25`
6. Make it visible to your profile, and add it to the page layout

### Using a different field name

If your org already has a body field with a different name (e.g. `Body__c`,
`Article_Body__c`, or you want to use the standard Knowledge `Summary` field)
you only need to change one line in the Apex class.

Open `AircallKBController` in Setup → Apex Classes and find:

```apex
private static final String BODY_FIELD = 'Answer__c';
```

Change it to your field's API name and save. The rest of the class adjusts
automatically — every query, render and sanitisation pass uses this constant.

---

## Step 3 — Deploy the Apex classes

The Apex code can be pasted directly into the Salesforce UI:

1. Open
   [`AircallKBController.cls`](../force-app/main/default/classes/AircallKBController.cls)
   from this repo and copy its full contents
2. In Salesforce: **Setup → Apex Classes → New**
3. Paste the contents and **Save**
4. Repeat for
   [`AircallKBControllerTest.cls`](../force-app/main/default/classes/AircallKBControllerTest.cls)
   — paste into a new Apex Class and save

The test class isn't required for the endpoint to work, but you'll need it if
you ever want to deploy this to a production org (Salesforce requires 75%
test coverage on production deploys).

---

## Step 4 — Create a Force.com Site

The endpoint is exposed via a classic **Force.com Site** (not Experience
Cloud). Force.com Sites allow unauthenticated REST access, which is what we
need for a public crawlable URL.

1. **Setup → Sites**
2. Accept the **Salesforce Sites Terms and Conditions** if you haven't yet
3. Click **New** and create the site:
   - **Site Label**: e.g. `Knowledge Base`
   - **Site Name**: e.g. `Knowledge_Base`
   - **Default Web Address**: pick a path, e.g. `kb`
   - **Active**: tick this
   - **Active Site Home Page**: pick any (e.g. `UnderConstruction`) — it
     won't be used since callers only ever hit the REST path
4. **Save**

Your endpoint base URL is now:

```
https://<your-domain>.my.salesforce-sites.com/<your-path>/services/apexrest/AircallKB/
```

---

## Step 5 — Set the PUBLIC_BASE_URL constant

Open `AircallKBController` in Setup → Apex Classes → **Edit** and update:

```apex
private static final String PUBLIC_BASE_URL =
    'https://<your-domain>.my.salesforce-sites.com/<your-path>/services/apexrest/AircallKB/';
```

This URL is used in the sitemap so crawlers can discover article URLs.

Save.

---

## Step 6 — Grant guest user permissions

The site's guest profile needs access to the Apex class and the Knowledge
object. This is the step most people miss.

1. **Setup → Sites** → click your site
2. Click **Public Access Settings**

On the guest profile page:

### Apex Class Access

1. Scroll to **Enabled Apex Class Access** → **Edit**
2. Add `AircallKBController` to the enabled list
3. **Save**

### Object permissions

1. **Object Settings → Knowledge**
2. Tick **Read** and **View All** on the object
3. On the field `Answer__c` (or whichever body field you're using), tick
   **Read Access**
4. **Save**

---

## Step 7 — Author and publish your first article

1. **App Launcher → Knowledge → New**
2. Fill in:
   - **Title** — e.g. `Store Locations`
   - **URL Name** — auto-generated from the title; this becomes the path
     segment in the public URL
   - **Answer** (rich-text body) — author your content (a table works well)
3. **Save**
4. Click **Publish**

### Crucial: Channel visibility

By default a published article is only visible internally. To expose it on
the public site:

1. Edit the article (or publish a new version)
2. Open the **Channels** panel
3. Tick **Public Knowledge Base**
4. **Save → Publish**

Only articles flagged for the **Public Knowledge Base** channel will appear
in the public site index and be served at their URL.

---

## Step 8 — Test

Open these in a browser:

- **Index** — `https://<your-domain>.my.salesforce-sites.com/<your-path>/services/apexrest/AircallKB/`
  Should list your article as a clickable link.
- **Article** — click the link, or hit
  `.../services/apexrest/AircallKB/<UrlName>`
  Should render as a clean HTML page.
- **Sitemap** — `.../services/apexrest/AircallKB/sitemap.xml`
  Should list all article URLs.

If you get an `INVALID_SESSION_ID` error, you've created an Experience Cloud
site instead of a Force.com Site — go back to Step 4.

If you get a `Not Found` response, check that:

- The article is **Published** (not Draft)
- The article has the **Public Knowledge Base** channel ticked
- The guest profile has **Read** and **View All** on Knowledge

---

## Step 9 — Add the URL to your ingestion tool

Whatever's consuming the content (Aircall AI agent, an internal crawler, a
search index, etc.) — point it at the **index URL**:

```
https://<your-domain>.my.salesforce-sites.com/<your-path>/services/apexrest/AircallKB/
```

The crawler will follow links from the index to each individual article.

From this point on, anything authored in Salesforce Knowledge and ticked for
**Public Knowledge Base** will be picked up automatically on the next crawl.

---

## Controlling which articles are public

By default this project filters on the **`IsVisibleInPkb`** field — the
standard Knowledge "Public Knowledge Base" channel checkbox. Only articles
with this ticked are surfaced.

This is the simplest control: admins use the existing Channels UI to decide
what's public. No new fields, no custom logic.

### Switching to a custom field

If you'd rather not use the Public Knowledge Base channel — for example, you
already use that channel for something else, or you want a separate "exposed
to AI agent" flag — create a custom checkbox on Knowledge (e.g.
`Visible_To_AI__c`) and update the Apex.

In `AircallKBController`, find the three places that filter on
`IsVisibleInPkb = true`:

- The `renderArticle` SOQL
- The `queryArticles` helper (which feeds index + sitemap)

Replace `IsVisibleInPkb = true` with `Visible_To_AI__c = true` (or whatever
your field name is) in each.

### Other filtering ideas

The same pattern works for any criteria you want:

- **Data Categories** — filter on a specific category like *AI Knowledge*
- **Record Types** — only expose articles of a specific record type
- **Validation Status** — only expose articles that have passed review

In each case the change is the same: adjust the `WHERE` clause in the two
SOQL queries.

---

## What gets exposed

Just to be explicit, the only fields exposed publicly are the ones the Apex
class queries: `Title`, `Summary`, `UrlName`, `LastPublishedDate`, and the
configured body field (e.g. `Answer__c`). Any other custom fields on
Knowledge are not surfaced.

If your knowledge base contains internal notes, draft comments, or fields
you don't want to surface publicly, keep them out of the body field — they
won't be exposed by this endpoint.
