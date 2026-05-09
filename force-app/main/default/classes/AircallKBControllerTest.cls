/**
 * AircallKBControllerTest
 * --------------------------------------------------------------------------
 * Unit tests for AircallKBController.
 *
 * The controller's data access layer queries Knowledge__kav, but Knowledge
 * publishing in test context has known platform limitations. To keep tests
 * deterministic and fast, we exercise the rendering pipeline directly via
 * @TestVisible accessors rather than round-tripping through real Knowledge
 * records.
 * --------------------------------------------------------------------------
 */
@IsTest
private class AircallKBControllerTest {

    // -----------------------------------------------------------------
    // slugify
    // -----------------------------------------------------------------

    @IsTest
    static void slugifyHandlesBasicString() {
        System.assertEquals('downtown-branch',
            AircallKBController.slugify('Downtown Branch'));
    }

    @IsTest
    static void slugifyStripsPunctuationAndCollapsesSpaces() {
        System.assertEquals('store-no-1-cbd',
            AircallKBController.slugify('Store #No. 1 (CBD)'));
    }

    @IsTest
    static void slugifyTrimsLeadingTrailingHyphens() {
        System.assertEquals('hello-world',
            AircallKBController.slugify('---Hello World!!!'));
    }

    @IsTest
    static void slugifyHandlesNullAndEmpty() {
        System.assertEquals('', AircallKBController.slugify(null));
        System.assertEquals('', AircallKBController.slugify(''));
        System.assertEquals('', AircallKBController.slugify('   '));
    }

    // -----------------------------------------------------------------
    // renderBody — sanitisation
    // -----------------------------------------------------------------

    @IsTest
    static void renderBodyStripsInlineStyles() {
        String input = '<p style="color: red; font-size: 14px;">Hello</p>';
        String output = AircallKBController.renderBody(input);
        System.assert(!output.contains('style='), 'Expected style attr to be stripped: ' + output);
        System.assert(output.contains('Hello'), 'Content should remain');
    }

    @IsTest
    static void renderBodyStripsClassAndId() {
        String input = '<p class="ql-align-center" id="x">Centered</p>';
        String output = AircallKBController.renderBody(input);
        System.assert(!output.contains('class='), 'Class attr should be stripped');
        System.assert(!output.contains('id='), 'Id attr should be stripped');
        System.assert(output.contains('Centered'), 'Content should remain');
    }

    @IsTest
    static void renderBodyUnwrapsFontTags() {
        String input = '<p><font color="red" face="Arial">Coloured</font> text</p>';
        String output = AircallKBController.renderBody(input);
        System.assert(!output.contains('<font'), 'Font tag should be unwrapped');
        System.assert(output.contains('Coloured'), 'Content should remain');
    }

    @IsTest
    static void renderBodyUnwrapsSpanTags() {
        String input = '<p><span style="font-weight:bold">Spanned</span></p>';
        String output = AircallKBController.renderBody(input);
        System.assert(!output.contains('<span'), 'Span should be unwrapped');
        System.assert(output.contains('Spanned'), 'Content should remain');
    }

    @IsTest
    static void renderBodyMapsLegacyTagsToModernEquivalents() {
        String input = '<p><b>bold</b> and <i>italic</i> and <strike>old</strike></p>';
        String output = AircallKBController.renderBody(input);
        System.assert(output.contains('<strong>bold</strong>'), 'b -> strong');
        System.assert(output.contains('<em>italic</em>'), 'i -> em');
        System.assert(output.contains('<s>old</s>'), 'strike -> s');
    }

    @IsTest
    static void renderBodyConvertsDivsToParagraphs() {
        String input = '<div>Block of text</div>';
        String output = AircallKBController.renderBody(input);
        System.assert(output.contains('<p>Block of text</p>'),
            'div should convert to p: ' + output);
    }

    @IsTest
    static void renderBodyRemovesImages() {
        String input = '<p>Before <img src="/sfc/servlet.shepherd/abc" alt="logo"> after</p>';
        String output = AircallKBController.renderBody(input);
        System.assert(!output.contains('<img'), 'Image tag should be removed');
    }

    @IsTest
    static void renderBodyStripsScriptAndIframe() {
        String input = '<p>Safe</p><script>alert(1)</script><iframe src="x"></iframe>';
        String output = AircallKBController.renderBody(input);
        System.assert(!output.contains('<script'), 'Script tag must be stripped');
        System.assert(!output.contains('<iframe'), 'Iframe tag must be stripped');
        System.assert(output.contains('Safe'), 'Safe content must remain');
    }

    @IsTest
    static void renderBodyStripsMsoConditionalComments() {
        String input = '<p>Text</p><!--[if gte mso 9]>junk<![endif]-->';
        String output = AircallKBController.renderBody(input);
        System.assert(!output.contains('mso'), 'MSO conditional comment should be stripped');
        System.assert(output.contains('Text'), 'Content remains');
    }

    @IsTest
    static void renderBodyCollapsesEmptyParagraphs() {
        String input = '<p>One</p><p></p><p><br></p><p>&nbsp;</p><p>Two</p>';
        String output = AircallKBController.renderBody(input);
        System.assert(output.contains('One'), 'First paragraph remains');
        System.assert(output.contains('Two'), 'Last paragraph remains');
        // Confirm no consecutive empty paragraphs leaked through
        System.assert(!output.contains('<p></p>'), 'Empty paragraphs removed');
    }

    @IsTest
    static void renderBodyHandlesNullAndEmpty() {
        System.assertEquals('', AircallKBController.renderBody(null));
        System.assertEquals('', AircallKBController.renderBody(''));
    }

    // -----------------------------------------------------------------
    // renderBody — table conversion
    // -----------------------------------------------------------------

    @IsTest
    static void renderBodyConvertsTableToSections() {
        String input =
            '<table><tbody>'
          + '<tr><th>Name</th><th>Address</th><th>Opening Hours</th></tr>'
          + '<tr><td>Downtown Branch</td><td>100 Main St</td><td>10am-11pm</td></tr>'
          + '<tr><td>Westside Branch</td><td>200 West Ave</td><td>11am-10pm</td></tr>'
          + '</tbody></table>';
        String output = AircallKBController.renderBody(input);

        System.assert(output.contains('<section class="kb-row" id="downtown-branch">'),
            'First section should have slugified id');
        System.assert(output.contains('<h2>Downtown Branch</h2>'),
            'First column becomes h2');
        System.assert(output.contains('class="kb-field kb-address"'),
            'Field gets class derived from header');
        System.assert(output.contains('The address is 100 Main St.'),
            'Cell rendered as prose');
        System.assert(output.contains('The opening hours is 10am-11pm.'),
            'Multi-word header lowered correctly');
        System.assert(output.contains('id="westside-branch"'),
            'Second row also becomes a section');
    }

    @IsTest
    static void renderBodyHandlesTableWithoutThHeaderRow() {
        // Toolbar-built tables emit only <td> — first row is conventionally the header
        String input =
            '<table><tbody>'
          + '<tr><td>Name</td><td>Phone</td></tr>'
          + '<tr><td>Branch A</td><td>02 9000 0000</td></tr>'
          + '</tbody></table>';
        String output = AircallKBController.renderBody(input);
        System.assert(output.contains('<h2>Branch A</h2>'),
            'Should still treat first row as headers when only td present');
        System.assert(output.contains('The phone is 02 9000 0000.'),
            'Should produce prose from td-only header row');
    }

    @IsTest
    static void renderBodySkipsBlankCells() {
        String input =
            '<table><tbody>'
          + '<tr><th>Name</th><th>Address</th><th>Notes</th></tr>'
          + '<tr><td>Branch A</td><td>100 Main St</td><td></td></tr>'
          + '</tbody></table>';
        String output = AircallKBController.renderBody(input);
        System.assert(output.contains('The address is 100 Main St.'),
            'Address should render');
        System.assert(!output.contains('The notes is .'),
            'Blank cells should be skipped, not rendered as empty prose');
    }

    @IsTest
    static void renderBodyPreservesNonTableContent() {
        String input = '<h2>Intro</h2><p>Some context.</p>'
            + '<table><tbody>'
            + '<tr><th>Name</th><th>Phone</th></tr>'
            + '<tr><td>Branch A</td><td>02 9000 0000</td></tr>'
            + '</tbody></table>'
            + '<p>Closing note.</p>';
        String output = AircallKBController.renderBody(input);
        System.assert(output.contains('<h2>Intro</h2>'), 'Pre-table heading preserved');
        System.assert(output.contains('Some context'), 'Pre-table prose preserved');
        System.assert(output.contains('<h2>Branch A</h2>'), 'Table converted');
        System.assert(output.contains('Closing note'), 'Post-table prose preserved');
    }

    @IsTest
    static void renderBodyFallsBackForSingleRowTable() {
        // Only headers, no data rows — can't meaningfully split
        String input = '<table><tbody><tr><th>Name</th><th>Phone</th></tr></tbody></table>';
        String output = AircallKBController.renderBody(input);
        // Should fall back to original (or empty) rather than crash
        System.assertNotEquals(null, output);
    }

    // -----------------------------------------------------------------
    // REST routing — exercises serve() with mocked RestContext
    // -----------------------------------------------------------------

    @IsTest
    static void serveReturns404ForUnknownArticle() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/AircallKB/this-does-not-exist';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        AircallKBController.serve();

        System.assertEquals(404, RestContext.response.statusCode,
            'Unknown article should return 404');
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('Not Found'), 'Body should include Not Found message');
    }

    @IsTest
    static void serveIndexReturnsHtml() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/AircallKB/';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        AircallKBController.serve();

        String body = RestContext.response.responseBody.toString();
        System.assert(body.startsWith('<!DOCTYPE html>'), 'Index returns HTML');
        System.assert(body.contains('<h1>Knowledge Base</h1>'), 'Index has heading');
    }

    @IsTest
    static void serveSitemapReturnsXml() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/AircallKB/sitemap.xml';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        AircallKBController.serve();

        String body = RestContext.response.responseBody.toString();
        System.assert(body.startsWith('<?xml'), 'Sitemap is XML');
        System.assert(body.contains('<urlset'), 'Sitemap has urlset element');
    }
}
