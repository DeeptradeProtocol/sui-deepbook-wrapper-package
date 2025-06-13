#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

class MoveCodeAnalyzer {
  constructor(options = {}) {
    this.options = {
      skipBlankLines: true,
      skipComments: true,
      showDetails: false,
      skipDeprecated: true, // Skip deprecated by default
      ...options,
    };

    // Extensible patterns for future features
    this.patterns = {
      singleLineComment: /^\s*\/\/.*$/,
      multiLineCommentStart: /^\s*\/\*.*$/,
      multiLineCommentEnd: /.*\*\/\s*$/,
      multiLineCommentFull: /^\s*\/\*.*\*\/\s*$/,
      docComment: /^\s*\/\/\/.*$/,
      blankLine: /^\s*$/,
      // Deprecated method patterns (based on actual codebase)
      deprecatedAttribute: /^\s*#?\s*\[?deprecated\b/i,
      deprecatedSectionHeader: /^\s*\/\/.*===.*deprecated.*===/i,
      deprecatedComment: /^\s*\/\/.*deprecated/i,
      deprecatedConstant: /^\s*const\s+.*deprecated.*:/i,
      deprecatedAbort: /^\s*abort\s+.*deprecated/i,
      // Generic patterns
      todoRemove: /\/\/.*TODO.*REMOVE/i,
      legacyCode: /\/\/.*LEGACY/i,
    };
  }

  isDeprecatedLine(line) {
    return (
      this.patterns.deprecatedAttribute.test(line) ||
      this.patterns.deprecatedSectionHeader.test(line) ||
      this.patterns.deprecatedComment.test(line) ||
      this.patterns.deprecatedConstant.test(line) ||
      this.patterns.deprecatedAbort.test(line) ||
      this.patterns.todoRemove.test(line) ||
      this.patterns.legacyCode.test(line)
    );
  }

  isDeprecatedAttribute(line) {
    return this.patterns.deprecatedAttribute.test(line);
  }

  isFunctionStart(line) {
    return /^\s*public\s+fun\s+|^\s*fun\s+/.test(line);
  }

  countBraces(line) {
    const openBraces = (line.match(/{/g) || []).length;
    const closeBraces = (line.match(/}/g) || []).length;
    return openBraces - closeBraces;
  }

  startsAttribute(line) {
    return /^\s*#\[/.test(line);
  }

  containsDeprecated(line) {
    // Only match 'deprecated' in attribute context, not in variable names or strings
    return /^\s*deprecated\s*\(/.test(line.trim());
  }

  startsFunctionBody(line) {
    return line.includes("{");
  }

  analyzeFile(filePath) {
    const content = fs.readFileSync(filePath, "utf8");
    const lines = content.split("\n");

    const stats = {
      total: lines.length,
      code: 0,
      comments: 0,
      blank: 0,
      deprecated: 0,
    };

    let inMultiLineComment = false;
    let inDeprecatedBlock = false;
    let braceDepth = 0;
    let lookingForDeprecated = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // Handle multi-line comments
      if (this.patterns.multiLineCommentStart.test(line) && !this.patterns.multiLineCommentFull.test(line)) {
        inMultiLineComment = true;
        stats.comments++;
        continue;
      }

      if (inMultiLineComment) {
        stats.comments++;
        if (this.patterns.multiLineCommentEnd.test(line)) {
          inMultiLineComment = false;
        }
        continue;
      }

      // Simplified deprecated block detection
      // Step 1: Start looking when we see #[
      if (this.startsAttribute(line)) {
        lookingForDeprecated = true;
      }

      // Step 2: If we find 'deprecated' while looking, start deprecated block
      if (lookingForDeprecated && this.containsDeprecated(line)) {
        inDeprecatedBlock = true;
        lookingForDeprecated = false;
        braceDepth = 0;
      }

      // Step 3: Track brace depth to know when function ends
      if (inDeprecatedBlock) {
        braceDepth += this.countBraces(line);

        // Exit when braces balance back to 0 (function complete)
        if (braceDepth <= 0 && line.includes("}")) {
          inDeprecatedBlock = false;
          braceDepth = 0;
        }
      }

      // Reset looking state if we go too far without finding deprecated
      if (lookingForDeprecated && this.isFunctionStart(line) && !inDeprecatedBlock) {
        lookingForDeprecated = false;
      }

      // Simplified line classification with proper prioritization
      if (this.patterns.blankLine.test(line)) {
        stats.blank++;
      } else if (
        this.patterns.docComment.test(line) ||
        this.patterns.singleLineComment.test(line) ||
        this.patterns.multiLineCommentFull.test(line)
      ) {
        stats.comments++;
      } else if (inDeprecatedBlock) {
        // Inside deprecated block - count as deprecated code (including attributes, function signature, body)
        stats.deprecated++;
      } else if (this.isDeprecatedLine(line)) {
        // Standalone deprecated markers (outside functions) - fallback case
        stats.deprecated++;
      } else {
        stats.code++;
      }
    }

    return stats;
  }

  analyzeDirectory(dirPath) {
    const results = {};
    const files = fs.readdirSync(dirPath);

    const moveFiles = files.filter((file) => file.endsWith(".move"));

    let totals = {
      total: 0,
      code: 0,
      comments: 0,
      blank: 0,
      deprecated: 0,
    };

    moveFiles.forEach((file) => {
      const filePath = path.join(dirPath, file);
      const stats = this.analyzeFile(filePath);
      results[file] = stats;

      // Add to totals
      Object.keys(totals).forEach((key) => {
        totals[key] += stats[key];
      });
    });

    return { files: results, totals };
  }

  analyzeTestDirectory(dirPath) {
    const results = {};

    let totals = {
      total: 0,
      code: 0,
      comments: 0,
      blank: 0,
      deprecated: 0, // Should be 0 for tests but keeping for consistency
    };

    // Recursively analyze test subdirectories
    const analyzeSubdir = (subDirPath, prefix = "") => {
      if (!fs.existsSync(subDirPath)) return;

      const items = fs.readdirSync(subDirPath);

      items.forEach((item) => {
        const itemPath = path.join(subDirPath, item);
        const stat = fs.statSync(itemPath);

        if (stat.isDirectory()) {
          // Recursively analyze subdirectories
          analyzeSubdir(itemPath, prefix + item + "/");
        } else if (item.endsWith(".move")) {
          // Analyze test file
          const stats = this.analyzeFile(itemPath);
          const key = prefix + item;
          results[key] = stats;

          // Add to totals
          Object.keys(totals).forEach((statKey) => {
            totals[statKey] += stats[statKey];
          });
        }
      });
    };

    analyzeSubdir(dirPath);
    return { files: results, totals };
  }

  getEffectiveLines(stats) {
    let effective = stats.total;

    if (this.options.skipBlankLines) {
      effective -= stats.blank;
    }

    if (this.options.skipComments) {
      effective -= stats.comments;
    }

    if (this.options.skipDeprecated) {
      effective -= stats.deprecated;
    }

    return Math.max(0, effective);
  }

  formatResults(sourcesAnalysis, testsAnalysis = null) {
    console.log("\n📊 Sui DeepBook Wrapper - Lines of Code Analysis");
    console.log("=".repeat(67));

    // Sources section
    this.formatSection("📁 Sources Analysis", sourcesAnalysis, true);

    // Tests section (if available)
    if (testsAnalysis && Object.keys(testsAnalysis.files).length > 0) {
      this.formatSection("🧪 Tests Analysis", testsAnalysis, false);
    }

    // Overall summary
    console.log("\n📊 Overall Summary:");
    const sourcesEffective = this.getEffectiveLines(sourcesAnalysis.totals);
    console.log(`🎯 Effective LoC (sources only): ${sourcesEffective} lines`);

    if (testsAnalysis && Object.keys(testsAnalysis.files).length > 0) {
      const testsEffective = this.getEffectiveLines(testsAnalysis.totals);
      console.log(`🧪 Test LoC: ${testsEffective} lines`);
      console.log(`📈 Total project lines: ${sourcesAnalysis.totals.total + testsAnalysis.totals.total} lines`);
    }

    if (sourcesAnalysis.totals.deprecated > 0) {
      console.log(
        `🔄 Note: ${sourcesAnalysis.totals.deprecated} deprecated method lines detected and excluded from effective count`,
      );
    }

    if (this.options.showDetails) {
      console.log("\n📋 Configuration:");
      console.log(`• Skip blank lines: ${this.options.skipBlankLines}`);
      console.log(`• Skip comments: ${this.options.skipComments}`);
      console.log(`• Skip deprecated: ${this.options.skipDeprecated}`);
    }
  }

  formatSection(title, analysis, showDeprecated) {
    console.log(`\n${title}:`);

    // Determine if we need wider columns for test files
    const isTestSection = title.includes("Tests");
    const moduleWidth = isTestSection ? 35 : 20;
    const totalWidth = isTestSection ? 85 : 67;

    console.log("-".repeat(totalWidth));

    const headers =
      "Module".padEnd(moduleWidth) + "Total".padEnd(8) + "Code".padEnd(8) + "Comments".padEnd(10) + "Blank".padEnd(8);
    if (showDeprecated) {
      console.log(headers + "Deprecated".padEnd(12));
    } else {
      console.log(headers);
    }
    console.log("-".repeat(totalWidth));

    // Sort files by code lines (descending)
    const sortedFiles = Object.entries(analysis.files).sort(([, a], [, b]) => b.code - a.code);

    sortedFiles.forEach(([file, stats]) => {
      let filename = file.replace(".move", "");

      // Truncate filename if it's too long for the column
      if (filename.length > moduleWidth - 1) {
        filename = filename.substring(0, moduleWidth - 4) + "...";
      }

      let row =
        filename.padEnd(moduleWidth) +
        stats.total.toString().padEnd(8) +
        stats.code.toString().padEnd(8) +
        stats.comments.toString().padEnd(10) +
        stats.blank.toString().padEnd(8);

      if (showDeprecated) {
        row += stats.deprecated.toString().padEnd(12);
      }
      console.log(row);
    });

    // Section totals
    console.log("-".repeat(totalWidth));
    let totalRow =
      "TOTAL".padEnd(moduleWidth) +
      analysis.totals.total.toString().padEnd(8) +
      analysis.totals.code.toString().padEnd(8) +
      analysis.totals.comments.toString().padEnd(10) +
      analysis.totals.blank.toString().padEnd(8);

    if (showDeprecated) {
      totalRow += analysis.totals.deprecated.toString().padEnd(12);
    }
    console.log(totalRow);

    // Section summary
    const fileCount = Object.keys(analysis.files).length;
    const fileType = showDeprecated ? "modules" : "test files";
    console.log(`\n📈 ${title.replace(":", "")} Summary:`);
    console.log(`• Total ${fileType}: ${fileCount}`);
    console.log(`• Raw lines: ${analysis.totals.total}`);
    console.log(`• Code lines: ${analysis.totals.code}`);
    console.log(
      `• Comment lines: ${analysis.totals.comments} (${((analysis.totals.comments / analysis.totals.total) * 100).toFixed(1)}%)`,
    );
    console.log(`• Blank lines: ${analysis.totals.blank}`);

    if (showDeprecated && analysis.totals.deprecated > 0) {
      console.log(
        `• Deprecated lines: ${analysis.totals.deprecated} (${((analysis.totals.deprecated / analysis.totals.total) * 100).toFixed(1)}%)`,
      );
    }
  }
}

// CLI handling
function main() {
  const args = process.argv.slice(2);
  const options = {};

  // Parse CLI arguments
  if (args.includes("--include-comments")) options.skipComments = false;
  if (args.includes("--include-blank")) options.skipBlankLines = false;
  if (args.includes("--include-deprecated")) options.skipDeprecated = false;
  if (args.includes("--details")) options.showDetails = true;
  if (args.includes("--help")) {
    console.log(`
Usage: node scripts/count-loc.js [options]

Options:
  --include-comments    Include comment lines in effective count
  --include-blank      Include blank lines in effective count  
  --include-deprecated  Include deprecated lines in effective count (default: excluded)
  --details           Show configuration details
  --help              Show this help message

Default: Counts only code lines (skips comments, blank lines, and deprecated code)

Deprecated Patterns Detected:
  • #[deprecated(...)]          - Sui deprecated attributes
  • // === Deprecated ===       - Section headers  
  • const EFunctionDeprecated   - Error constants
  • abort EFunctionDeprecated   - Abort statements
  • // Deprecated comments      - Comment markers
`);
    return;
  }

  const analyzer = new MoveCodeAnalyzer(options);
  const sourcesPath = path.join(__dirname, "..", "packages", "deepbook-wrapper", "sources");
  const testsPath = path.join(__dirname, "..", "packages", "deepbook-wrapper", "tests");

  if (!fs.existsSync(sourcesPath)) {
    console.error("❌ Sources directory not found:", sourcesPath);
    console.log("Make sure you're running this from the project root directory.");
    return;
  }

  try {
    // Analyze sources
    const sourcesAnalysis = analyzer.analyzeDirectory(sourcesPath);

    // Analyze tests (optional)
    let testsAnalysis = null;
    if (fs.existsSync(testsPath)) {
      testsAnalysis = analyzer.analyzeTestDirectory(testsPath);
    }

    // Display results
    analyzer.formatResults(sourcesAnalysis, testsAnalysis);
  } catch (error) {
    console.error("❌ Error analyzing files:", error.message);
  }
}

if (require.main === module) {
  main();
}

module.exports = MoveCodeAnalyzer;
