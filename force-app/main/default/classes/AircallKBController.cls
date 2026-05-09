/**
 * AircallKBController
 * --------------------------------------------------------------------------
 * Public REST endpoint that exposes published Salesforce Knowledge articles
 * as clean, semantic HTML pages suitable for crawling by AI knowledge-base
 * ingestion tools (e.g. Aircall's webcrawler).
 *
 * The class:
 *   - Lists all articles flagged visible to the Public Knowledge Base
 *   - Renders each article from its rich-text body field
 *   - Sanitises and normalises output from the Lightning rich-text editor
 *   - Converts tabular content into prose-style sections (voice-friendly)
 *   - Emits a sitemap.xml for crawler discovery
 *
 * Configuration:
 *   - BODY_FIELD: the API name of the rich-text field on Knowledge__kav
 *   - LANGUAGE  : the language code to publish (default org Knowledge lang)
 *   - PUBLIC_BASE_URL: the public site base URL used in the sitemap
 *
 * Endpoints (relative to /services/apexrest/AircallKB/):
 *   GET /                  -> index page listing all articles
 *   GET /<UrlName>         -> single article rendered as HTML
 *   GET /sitemap.xml       -> XML sitemap for crawler
 * --------------------------------------------------------------------------
 */
@RestResource(urlMapping='/AircallKB/*')
global class AircallKBController {

    // -----------------------------------------------------------------
    // Configuration — adjust per customer org
    // -----------------------------------------------------------------
    private static final String BODY_FIELD = 'Answer__c';
    private static final String LANGUAGE   = 'en_US';
    private static final String PUBLIC_BASE_URL =
        'https://your-domain.my.salesforce-sites.com'
        + '/kb/services/apexrest/AircallKB/';

    // -----------------------------------------------------------------
    // Routing
    // -----------------------------------------------------------------
    @HttpGet
    global static void serve() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String path = req.requestURI.substringAfter('/AircallKB');
        if (path.startsWith('/')) path = path.substring(1);
        path = path.removeEnd('/');

        if (String.isBlank(path)) {
            res.addHeader('Content-Type', 'text/html; charset=UTF-8');
            res.responseBody = Blob.valueOf(renderIndex());
        } else if (path == 'sitemap.xml') {
            res.addHeader('Content-Type', 'application/xml; charset=UTF-8');
            res.responseBody = Blob.valueOf(renderSitemap());
        } else {
            res.addHeader('Content-Type', 'text/html; charset=UTF-8');
            res.responseBody = Blob.valueOf(renderArticle(path));
        }
    }

    // -----------------------------------------------------------------
    // Index page
    // -----------------------------------------------------------------
    private static String renderIndex() {
        List<Knowledge__kav> articles = queryArticles(false);
        List<String> out = new List<String>();
        out.add('<!DOCTYPE html><html lang="en"><head>');
        out.add('<meta charset="UTF-8">');
        out.add('<meta name="viewport" content="width=device-width, initial-scale=1">');
        out.add('<title>Knowledge Base</title>');
        out.add('<meta name="description" content="Index of all published knowledge articles.">');
        out.add('</head><body>');
        out.add('<main><article>');
        out.add('<header><h1>Knowledge Base</h1>');
        out.add('<p>The following articles are available.</p></header>');
        out.add('<ul>');
        for (Knowledge__kav a : articles) {
            out.add('<li><a href="' + PUBLIC_BASE_URL + a.UrlName + '">'
                  + a.Title.escapeHtml4() + '</a></li>');
        }
        out.add('</ul>');
        out.add('</article></main></body></html>');
        return String.join(out, '');
    }

    // -----------------------------------------------------------------
    // Single article
    // -----------------------------------------------------------------
    private static String renderArticle(String urlName) {
        String soql =
            'SELECT Title, Summary, UrlName, LastPublishedDate, ' + BODY_FIELD + ' '
            + 'FROM Knowledge__kav '
            + 'WHERE UrlName = :urlName '
            +   'AND PublishStatus = \'Online\' '
            +   'AND Language = :LANGUAGE '
            +   'AND IsVisibleInPkb = true '
            + 'LIMIT 1';
        List<Knowledge__kav> articles = Database.query(soql);

        if (articles.isEmpty()) {
            RestContext.response.statusCode = 404;
            return notFoundPage();
        }

        Knowledge__kav a = articles[0];
        String rawBody = (String) a.get(BODY_FIELD);
        String body = renderBody(rawBody);

        String safeTitle = a.Title == null ? '' : a.Title.escapeHtml4();
        String summary = String.isBlank(a.Summary) ? safeTitle : a.Summary.escapeHtml4();

        List<String> out = new List<String>();
        out.add('<!DOCTYPE html><html lang="en"><head>');
        out.add('<meta charset="UTF-8">');
        out.add('<meta name="viewport" content="width=device-width, initial-scale=1">');
        out.add('<title>' + safeTitle + '</title>');
        out.add('<meta name="description" content="' + summary + '">');
        out.add('<meta property="og:title" content="' + safeTitle + '">');
        out.add('<meta property="og:description" content="' + summary + '">');
        out.add('<meta property="og:type" content="article">');
        out.add('</head><body>');
        out.add('<main><article>');
        out.add('<header><h1>' + safeTitle + '</h1>');
        if (!String.isBlank(a.Summary)) {
            out.add('<p>' + a.Summary.escapeHtml4() + '</p>');
        }
        out.add('</header>');
        out.add(body);
        if (a.LastPublishedDate != null) {
            out.add('<footer><p>Last updated: '
                  + a.LastPublishedDate.format('d MMMM yyyy') + '</p></footer>');
        }
        out.add('</article></main></body></html>');
        return String.join(out, '');
    }

    private static String notFoundPage() {
        return '<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">'
             + '<title>Not Found</title></head><body><main><article>'
             + '<h1>Not Found</h1><p>The article you requested does not exist.</p>'
             + '</article></main></body></html>';
    }

    // -----------------------------------------------------------------
    // Sitemap
    // -----------------------------------------------------------------
    private static String renderSitemap() {
        List<Knowledge__kav> articles = queryArticles(false);
        List<String> out = new List<String>();
        out.add('<?xml version="1.0" encoding="UTF-8"?>');
        out.add('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
        out.add('<url><loc>' + PUBLIC_BASE_URL + '</loc></url>');
        for (Knowledge__kav a : articles) {
            out.add('<url><loc>' + PUBLIC_BASE_URL + a.UrlName + '</loc></url>');
        }
        out.add('</urlset>');
        return String.join(out, '');
    }

    // -----------------------------------------------------------------
    // Shared query
    // -----------------------------------------------------------------
    private static List<Knowledge__kav> queryArticles(Boolean includeBody) {
        String fields = 'Title, UrlName';
        if (includeBody) fields += ', ' + BODY_FIELD + ', Summary, LastPublishedDate';
        String soql =
            'SELECT ' + fields + ' '
            + 'FROM Knowledge__kav '
            + 'WHERE PublishStatus = \'Online\' '
            +   'AND Language = :LANGUAGE '
            +   'AND IsVisibleInPkb = true '
            + 'ORDER BY Title';
        return Database.query(soql);
    }

    // =================================================================
    // BODY RENDERING — sanitise + normalise rich-text editor output
    // =================================================================

    /**
     * Top-level body renderer. Order of operations is deliberate:
     * 1. Strip dangerous/unwanted constructs (defensive belt-and-braces)
     * 2. Normalise legacy/inconsistent inline formatting
     * 3. Strip noisy attributes (style, class, id, mso-*, data-*, ql-*)
     * 4. Drop images (Salesforce internal src URLs won't resolve publicly)
     * 5. Collapse whitespace and remove empty paragraphs
     * 6. Convert tables to prose-style sections
     */
    @TestVisible
    private static String renderBody(String raw) {
        if (String.isBlank(raw)) return '';
        String s = raw;
        s = stripUnsafe(s);
        s = normaliseInline(s);
        s = stripNoisyAttributes(s);
        s = stripImages(s);
        s = collapseWhitespace(s);
        s = tablesToSections(s);
        return s;
    }

    /** Belt-and-braces removal of tags Salesforce should already have stripped. */
    private static String stripUnsafe(String s) {
        s = s.replaceAll('(?is)<(script|style|iframe|object|embed|form|input|link|meta)\\b[^>]*>.*?</\\1>', '');
        s = s.replaceAll('(?is)<(script|style|iframe|object|embed|form|input|link|meta)\\b[^>]*/?>', '');
        // Strip MS Word conditional comments left behind by paste
        s = s.replaceAll('(?is)<!--\\[if[^\\]]*\\]>.*?<!\\[endif\\]-->', '');
        s = s.replaceAll('(?is)<!--.*?-->', '');
        return s;
    }

    /**
     * Normalise inline elements emitted inconsistently by the editor:
     *   <font>, <b>, <i>, <strike>, <span> -> standard or unwrapped
     *   <div> -> <p>
     */
    private static String normaliseInline(String s) {
        // <font> just wraps text — drop the wrapper
        s = s.replaceAll('(?is)<font\\b[^>]*>(.*?)</font>', '$1');
        // <span> typically only carries presentational style — drop the wrapper
        s = s.replaceAll('(?is)<span\\b[^>]*>(.*?)</span>', '$1');
        // Map deprecated formatting to modern equivalents
        s = s.replaceAll('(?is)<b\\b[^>]*>(.*?)</b>', '<strong>$1</strong>');
        s = s.replaceAll('(?is)<i\\b[^>]*>(.*?)</i>', '<em>$1</em>');
        s = s.replaceAll('(?is)<strike\\b[^>]*>(.*?)</strike>', '<s>$1</s>');
        // <div> -> <p> for semantic consistency
        s = s.replaceAll('(?is)<div\\b[^>]*>', '<p>');
        s = s.replaceAll('(?is)</div>', '</p>');
        return s;
    }

    /**
     * Strip presentational + extraneous attributes that the rich-text
     * editor or pasted content can leave behind. We keep:
     *   - href, target on <a>
     *   - colspan, rowspan on <td>/<th>
     *   - alt on <img> (image tag itself is removed later)
     */
    private static String stripNoisyAttributes(String s) {
        // style="..." (single + double quotes)
        s = s.replaceAll('(?is)\\s+style\\s*=\\s*"[^"]*"', '');
        s = s.replaceAll('(?is)\\s+style\\s*=\\s*\'[^\']*\'', '');
        // class="..."
        s = s.replaceAll('(?is)\\s+class\\s*=\\s*"[^"]*"', '');
        s = s.replaceAll('(?is)\\s+class\\s*=\\s*\'[^\']*\'', '');
        // id="..."
        s = s.replaceAll('(?is)\\s+id\\s*=\\s*"[^"]*"', '');
        s = s.replaceAll('(?is)\\s+id\\s*=\\s*\'[^\']*\'', '');
        // data-* (Salesforce file references etc.)
        s = s.replaceAll('(?is)\\s+data-[a-z-]+\\s*=\\s*"[^"]*"', '');
        s = s.replaceAll('(?is)\\s+data-[a-z-]+\\s*=\\s*\'[^\']*\'', '');
        // Common presentational attributes
        s = s.replaceAll('(?is)\\s+(align|valign|width|height|border|cellpadding|cellspacing|bgcolor|color|face|size|nowrap|dir|lang|title|spellcheck|tabindex)\\s*=\\s*"[^"]*"', '');
        s = s.replaceAll('(?is)\\s+(align|valign|width|height|border|cellpadding|cellspacing|bgcolor|color|face|size|nowrap|dir|lang|title|spellcheck|tabindex)\\s*=\\s*\'[^\']*\'', '');
        return s;
    }

    /**
     * Images uploaded via the Knowledge editor get a Salesforce-internal
     * src URL that won't resolve for an unauthenticated public visitor
     * (or our crawler). Strip the tag entirely — alt text is lost, but
     * a broken image is worse than no image.
     */
    private static String stripImages(String s) {
        return s.replaceAll('(?is)<img\\b[^>]*/?>', '');
    }

    /**
     * Quill emits <p><br></p> as an "empty line" marker and &nbsp; as
     * non-breaking space. Both are noise in our rendered output.
     */
    private static String collapseWhitespace(String s) {
        s = s.replace('&nbsp;', ' ');
        // Empty paragraphs in their various forms
        s = s.replaceAll('(?is)<p>\\s*</p>', '');
        s = s.replaceAll('(?is)<p>\\s*<br\\s*/?>\\s*</p>', '');
        // Collapse runs of whitespace inside text nodes
        s = s.replaceAll('[ \\t]+', ' ');
        return s.trim();
    }

    // =================================================================
    // TABLE PROCESSING
    //
    // Each <table> in the body is detected and converted into one
    // <section> per data row, with prose paragraphs per cell. This
    // preserves all data while producing output that a voice agent
    // can read aloud naturally and a crawler can semantically index.
    // =================================================================

    private static String tablesToSections(String html) {
        if (html == null || !html.contains('<table')) return html;

        List<String> result = new List<String>();
        Matcher tableMatcher = Pattern.compile('(?is)<table\\b[^>]*>(.*?)</table>').matcher(html);
        Integer cursor = 0;

        while (tableMatcher.find()) {
            // Append everything before this table unchanged
            result.add(html.substring(cursor, tableMatcher.start()));

            String tableInner = tableMatcher.group(1);
            String converted = convertSingleTable(tableInner);
            // If conversion yields nothing useful, fall back to original
            result.add(String.isBlank(converted) ? tableMatcher.group(0) : converted);

            cursor = tableMatcher.end();
        }
        result.add(html.substring(cursor));
        return String.join(result, '');
    }

    /**
     * Convert one table's inner HTML into a series of <section> blocks.
     *
     * Heuristic for headers:
     *   - If the first row contains <th>, use those as headers
     *   - Otherwise treat the first row as headers (toolbar-built tables
     *     emit only <td> — the first row is conventionally the header)
     *
     * If a table has only one row, we can't meaningfully split — return
     * empty string so the caller falls back to the raw table.
     */
    private static String convertSingleTable(String tableInner) {
        List<List<String>> rows = parseRows(tableInner);
        if (rows.size() < 2) return '';

        List<String> headers = rows[0];
        List<String> out = new List<String>();

        for (Integer i = 1; i < rows.size(); i++) {
            List<String> row = rows[i];
            if (row.isEmpty()) continue;

            String subjectRaw = row[0];
            if (String.isBlank(subjectRaw)) continue;
            String subject = subjectRaw.escapeHtml4();
            String sectionId = slugify(subjectRaw);

            out.add('<section class="kb-row" id="' + sectionId + '">');
            out.add('<h2>' + subject + '</h2>');
            for (Integer j = 1; j < row.size() && j < headers.size(); j++) {
                if (String.isBlank(row[j])) continue;
                String headerLabel = headers[j].toLowerCase();
                String value = row[j].escapeHtml4();
                String fieldClass = 'kb-field kb-' + slugify(headers[j]);
                out.add('<p class="' + fieldClass + '">'
                      + 'The ' + headerLabel.escapeHtml4() + ' is ' + value + '.</p>');
            }
            out.add('</section>');
        }
        return String.join(out, '');
    }

    /**
     * Parse the inner HTML of a table into a list of rows of cell texts.
     * Cell content has tags stripped — table values are expected to be
     * short factual strings, not nested HTML.
     */
    private static List<List<String>> parseRows(String tableInner) {
        List<List<String>> rows = new List<List<String>>();
        Matcher rowMatcher = Pattern.compile('(?is)<tr\\b[^>]*>(.*?)</tr>').matcher(tableInner);
        while (rowMatcher.find()) {
            List<String> cells = new List<String>();
            Matcher cellMatcher = Pattern.compile('(?is)<t[hd]\\b[^>]*>(.*?)</t[hd]>').matcher(rowMatcher.group(1));
            while (cellMatcher.find()) {
                cells.add(stripTags(cellMatcher.group(1)).trim());
            }
            if (!cells.isEmpty()) rows.add(cells);
        }
        return rows;
    }

    // =================================================================
    // HELPERS
    // =================================================================

    private static String stripTags(String s) {
        if (s == null) return '';
        // Drop all tags, decode &nbsp;, collapse whitespace
        String r = s.replaceAll('(?is)<[^>]+>', ' ');
        r = r.replace('&nbsp;', ' ');
        r = r.replaceAll('\\s+', ' ');
        return r.trim();
    }

    /** "Downtown Branch" -> "downtown-branch" */
    @TestVisible
    private static String slugify(String s) {
        if (s == null) return '';
        String slug = s.toLowerCase().replaceAll('[^a-z0-9]+', '-');
        return slug.removeStart('-').removeEnd('-');
    }
}
