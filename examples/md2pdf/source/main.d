static import std.file;
import std.stdio;
import std.conv;
import std.format;
import std.algorithm;

import printed.canvas;
import printed.flow;
import commonmarkd;
import yxml;
import consolecolors;

void usage()
{
    cwriteln("Usage:".white);
    cwriteln("        md2pdf input0.md ... inputN.md [-o output.pdf][--html output.html]".cyan);
    cwriteln();
    cwriteln("Description:".white);
    cwriteln("        Converts CommonMark to PDF.");
    cwriteln;
    cwriteln("Flags:".white);
    cwriteln("        -h, --help  Shows this help");
    cwriteln("        -o          Output file path (default: output.pdf)");
    cwriteln("        --html      Output intermediate HTML (default: no output)");
    cwriteln;
}

int main(string[] args)
{
    try
    {
        bool help = false;
        string[] inputPathes = [];
        string outputPath = "output.pdf";
        string htmlPath = null;

        for (int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-h" || arg == "--help")
                help = true;
            else if (arg == "-o")
            {
                ++i;
                outputPath = args[i];
            }
            else if (arg == "--html")
            {
                if (i + 1 < args.length)
                {
                    if (endsWith(args[i], ".html"))
                    {
                        ++i;
                        htmlPath = args[i];
                    }
                }
                if (htmlPath == null)
                {
                    htmlPath = "output.html";
                }
            }
            else
            {
                inputPathes ~= args[i];
            }
        }

        if (help)
        {
            usage();
            return 1;
        }

        if (inputPathes.length == 0) 
            throw new Exception("Need Markdown input files. Use --help for usage.");

        // Concatenate the markdown files
        string concatMD = "";
        foreach(input; inputPathes)
        {
            concatMD ~= cast(string) std.file.read(input);
        }

        string html = concatMD.convertMarkdownToHTML;

        foreach(size_t n, char ch; html)
        {
            if (ch == 0)
                throw new Exception("Null byte found in file, is this really Markdown?");
        }

        string fullHTML = 
            "<html>\n" ~
            "<body>\n" ~
            html ~
            "</body>\n" ~
            "</html>\n";

        if (htmlPath)
        {
            std.file.write(htmlPath, fullHTML);
            cwritefln(" =&gt; Written HTML %s (%s)".green, htmlPath, prettyByteSize(fullHTML.length));
        }

        // Parse DOM
        XmlDocument dom;
        dom.parse(fullHTML);
        if (dom.isError)
            throw new Exception(dom.errorMessage.idup);

        int widthMm = 210;
        int heightMm = 297;
        auto pdf = new PDFDocument(widthMm, heightMm);

        StyleOptions style;
        style.fontFace = "Arial";

        IFlowDocument doc = new FlowDocument(pdf, style);

        // Traverse HTML and generate corresponding IFlowDocument commands

        XmlElement bodyNode = dom.root;
        assert(bodyNode !is null);

        void renderNode(XmlNode elem)
        {
            // If it's a text node, display text
            if (auto textNode = cast(XmlText)elem)
            {
                const(char)[] s = textNode.textContent();
                doc.text(s);
            }
            else if (auto e = cast(XmlElement)elem)
            {
                debug(domTraversal) writeln(">", e.tagName);
                // Enter the node
                switch(e.tagName)
                {
                    case "p": doc.enterParagraph(); break;
                    case "b": doc.enterB(); break;
                    case "strong": doc.enterStrong(); break;
                    case "i": doc.enterI(); break;
                    case "em": doc.enterEm(); break;
                    case "code": doc.enterCode(); break;
                    case "pre": doc.enterPre(); break;
                    case "h1": doc.enterH1(); break;
                    case "h2": doc.enterH2(); break;
                    case "h3": doc.enterH3(); break;
                    case "h4": doc.enterH4(); break;
                    case "h5": doc.enterH5(); break;
                    case "h6": doc.enterH6(); break;
                    case "ol": doc.enterOrderedList(); break;
                    case "ul": doc.enterUnorderedList(); break;
                    case "li": doc.enterListItem(); break;
                    case "img": 
                    {
                        const(char)[] src = e.getAttribute("src");
                        doc.enterImage(src); 
                        break;
                    }
                    default:
                        break;
                }

                // Render children
                foreach(c; e.childNodes)
                    renderNode(c);

                // Exit the node
                switch(e.tagName)
                {
                    case "html": doc.finalize(); break;
                    case "p": doc.exitParagraph(); break;
                    case "b": doc.exitB(); break;
                    case "strong": doc.exitStrong(); break;
                    case "i": doc.exitI(); break;
                    case "em": doc.exitEm(); break;
                    case "code": doc.exitCode(); break;
                    case "pre": doc.exitPre(); break;
                    case "h1": doc.exitH1(); break;
                    case "h2": doc.exitH2(); break;
                    case "h3": doc.exitH3(); break;
                    case "h4": doc.exitH4(); break;
                    case "h5": doc.exitH5(); break;
                    case "h6": doc.exitH6(); break;
                    case "br": doc.br(); break; // MAYDO: not sure where a HTML br tag with text inside would put the line break
                    case "ol": doc.exitOrderedList(); break;
                    case "ul": doc.exitUnorderedList(); break;
                    case "li": doc.exitListItem(); break;
                    case "img": doc.exitImage(); break;
                    default:
                        break;
                }
                debug(domTraversal) writeln("<", e.tagName);
            }
        }

        renderNode(bodyNode);

        const(ubyte)[] bytes = pdf.bytes();

        std.file.write(outputPath, bytes);
        cwritefln(" =&gt; Written PDF %s (%s)".green, outputPath, prettyByteSize(bytes.length));
        return 0;
    }
    catch(CCLException e)
    {
        error(e.msg);
        return 2;
    }
    catch(Exception e)
    {
        error(escapeCCL(e.message));
        return 2;
    }
}

void error(const(char)[] msg)
{
    cwritefln("error: %s".lred, msg);
}

string prettyByteSize(size_t size)
{
    if (size < 10000)
        return format("%s bytes", size);
    else if (size < 1024*1024)
        return format("%s kb", (size + 512) / 1024);
    else
        return format("%s mb", (size + 1024*512) / (1024*1024));
}