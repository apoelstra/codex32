{ pkgs ? import <nixpkgs> { }
, stdenv ? pkgs.stdenv
, lib ? pkgs.lib
, ghostscript ? pkgs.ghostscript
, ref ? null
, doPdfGeneration ? true
  # Attempts to render every page individually to make sure the dependencies
  # are set correctly.
, doCheck ? true
  # Checks whether the generated output matches the checked-in SSS32.ps.
  # When doing development you may want to shut this off to obtain the
  # output file that you need to check in.
  #
  # Has no effect if doChecks is not set.
, doOutputDiff ? true
}:

let
  src =
    if isNull ref
    then lib.sourceFilesBySuffices ./. [ ".ps" ".inc" ]
    else
      fetchGit {
        url = ./.;
        inherit ref;
      };
  shortId = lib.optionalString (! isNull ref) ("-" + builtins.substring 0 8 src.rev);

  setup = rec {
    frontMatter = {
      content = builtins.readFile "${src}/include/setup/front-matter.ps.inc";
      dependencies = [ ];
    };
    helpers = {
      content = builtins.readFile "${src}/include/setup/helpers.ps.inc";
      dependencies = [ ];
    };
    field = {
      content = builtins.readFile "${src}/include/setup/field.ps.inc";
      dependencies = [ ];
    };
    code = {
      content = builtins.readFile "${src}/include/setup/code.ps.inc";
      dependencies = [ ];
    };
    bch = {
      content = builtins.readFile "${src}/include/setup/bch.ps.inc";
      dependencies = [ ];
    };
    graphicsHelpers = {
      content = builtins.readFile "${src}/include/setup/graphics-helpers.ps.inc";
      dependencies = [ ];
    };
    graphicsVolvelles = {
      content = builtins.readFile "${src}/include/setup/graphics-volvelles.ps.inc";
      dependencies = [
        field
        code
        helpers # for determinant
        graphicsHelpers # for verythin
      ];
    };
    reference = {
      content = builtins.readFile "${src}/include/setup/reference.ps.inc";
      dependencies = [
        code
      ];
    };
    shareTables = {
      content = builtins.readFile "${src}/include/setup/share-tables.ps.inc";
      dependencies = [ field code ];
    };
    checksumTable = {
      content = builtins.readFile "${src}/include/setup/checksum-table.ps.inc";
      dependencies = [ field code bch ];
    };
    checksumWorksheet = {
      content = builtins.readFile "${src}/include/setup/checksum-worksheet.ps.inc";
      dependencies = [
        field
        bch
        graphicsHelpers # for codexcentreshow
      ];
    };
  };
  # Dependencies that every page has
  standardDependencies = with setup; [
    frontMatter # for ver, in each page footer
    graphicsHelpers # for portraitPage and landscapePage
  ];

  allPages = {
    title = {
      sourceHeader = "Title Page";
      content = builtins.readFile "${src}/include/title.ps.inc";
      # These dependencies are entirely to force the ordering of the setup
      # code in the full booklet. None are needed, and they will be removed
      # in a later commit (which will have a ton of moved code in SSS32.ps,
      # which we're trying to avoid for now).
      dependencies = with setup; [
        frontMatter
        helpers
        field
        code
        bch
        graphicsVolvelles
        graphicsHelpers
        reference
        shareTables
        checksumTable
      ];
      skipPageNumber = true;
    };
    license = {
      sourceHeader = "License Information";
      content = builtins.readFile "${src}/include/license.ps.inc";
      dependencies = [ ];
      skipPageNumber = true;
    };
    reference = {
      sourceHeader = "Reference Sheet";
      content = builtins.readFile "${src}/include/reference.ps.inc";
      dependencies = with setup; [ reference ];
      drawFooter = true;
    };
    principalTables = {
      sourceHeader = "Arithmetic Tables";
      content = builtins.readFile "${src}/include/principal-tables.ps.inc";
      dependencies = with setup; [ field code ];
    };

    additionBottom = {
      content = "{xor} (Addition) code dup perm drawBottomWheelPage\n";
      dependencies = with setup; [ code graphicsVolvelles ]; # for pgsize
    };
    additionTop = {
      content = "showTopWheelPage\n";
      dependencies = with setup; [ code graphicsVolvelles ]; # for pgsize
    };
    recovery = {
      content = builtins.readFile "${src}/include/volvelle-recovery.ps.inc";
      dependencies = with setup; [ graphicsVolvelles ]; # for portraitPage
    };
    fusionInner = {
      content = builtins.readFile "${src}/include/volvelle-fusion-1.ps.inc";
      dependencies = with setup; [ graphicsVolvelles ]; # for portraitPage
    };
    fusionOuter = {
      content = builtins.readFile "${src}/include/volvelle-fusion-2.ps.inc";
      dependencies = with setup; [ graphicsVolvelles ]; # for portraitPage
    };

    generationInstructions = {
      content = builtins.readFile "${src}/include/page7.ps.inc";
      dependencies = with setup; [
        code
        checksumWorksheet # for showParagraphs
      ];
    };

    checksumTable1 = {
      content = builtins.readFile "${src}/include/checksum-table-1.ps.inc";
      isLandscape = true;
      dependencies = with setup; [ checksumTable ];
      drawFooter = true;
    };
    checksumTable2 = {
      content = builtins.readFile "${src}/include/checksum-table-2.ps.inc";
      dependencies = with setup; [ checksumTable ];
      isLandscape = true;
      drawFooter = true;
    };
    checksumWorksheet = {
      content = builtins.readFile "${src}/include/checksum-worksheet.ps.inc";
      dependencies = with setup; [ code checksumWorksheet ];
      isLandscape = true;
      drawFooter = true;
    };

    shareTable = a: b: c: d: {
      content = "${toString a} ${toString b} ${toString c} ${toString d} showShareTablePage\n";
      dependencies = with setup; [ shareTables ];
      drawFooter = true;
    };
  };

  fullBooklet = {
    name = "SSS32.ps";
    pages = with allPages; [
      title
      license
      reference
      principalTables
      additionBottom
      additionTop
      generationInstructions
      (shareTable 29 24 13 25)
      (shareTable 9 8 23 18)
      (shareTable 22 31 27 19)
      (shareTable 1 0 3 16)
      (shareTable 11 28 12 14)
      (shareTable 6 4 2 15)
      (shareTable 10 17 21 20)
      (shareTable 26 30 7 5)
      recovery
      fusionInner
      fusionOuter
      checksumTable1
      checksumTable2
      checksumWorksheet
    ];
  };

  dependencyContentRecur = content: builtins.concatMap
    (item: (dependencyContentRecur item.dependencies) ++ [ item.content ])
    content;
  dependencyContent = pages: lib.lists.unique (
    (builtins.concatMap (page: dependencyContentRecur page.dependencies) pages) ++
    (map (dep: dep.content) standardDependencies)
  );

  renderBooklet = booklet:
    let
      addPage = content: pageData: {
        content = content.content + lib.optionalString (pageData ? sourceHeader) ''
          %****************************************************************
          %*
          %* ${pageData.sourceHeader}
          %*
          %****************************************************************
        '' + ''
          %%Page: ${toString content.nextPgIdx} ${toString content.nextPgIdx}
          ${lib.optionalString (pageData ? isLandscape) "%%PageOrientation: Landscape\n"}
          %%BeginPageSetup
          /pgsave save def
          %%EndPageSetup
          ${if pageData ? isLandscape then "landscapePage" else "portraitPage"} begin
          ${lib.optionalString (pageData ? drawFooter) "${toString content.nextFooterIdx} drawFooter"}
          ${pageData.content}
          end
          pgsave restore
          showpage
        '';
        nextFooterIdx = content.nextFooterIdx + (if pageData ? drawFooter then 1 else 0);
        nextPgIdx = content.nextPgIdx + 1;
      };
      initialContent = {
        content = ''
          %!PS-Adobe-3.0
          %%Orientation: Portrait
          %%Pages: ${toString (builtins.length booklet.pages)}
          %%EndComments
          %%BeginSetup
          ${builtins.concatStringsSep "\n" (dependencyContent booklet.pages)}%%EndSetup

          %************************************************************************
          %************************************************************************
          %*
          %* Section Three: Page Rendering
          %*
          %************************************************************************
          %************************************************************************

        '';
        nextPgIdx = 1;
        nextFooterIdx = 1;
      };
      finalContent = builtins.foldl' addPage initialContent booklet.pages;
    in
    pkgs.writeTextFile {
      name = booklet.name;
      text = finalContent.content + ''
        %%EOF
      '';
    };
  checkSinglePage = page: renderBooklet {
    name = "test-single-page.ps";
    pages = [ page ];
  };
in
stdenv.mkDerivation {
  name = "codex32${shortId}";

  buildInputs = if doCheck || doPdfGeneration then [ ghostscript ] else [ ];

  phases = [ "buildPhase" ] ++ lib.optionals doCheck [ "checkPhase" ];

  buildPhase = ''
    set -e

    ghostscriptTest() {
      echo "Ghostscript testing $1"
      local output;
      if ! output="$(gs -dNOPAUSE -dNODISPLAY "$1" < /dev/null 2>&1)"; then
        echo "Failed to run ghostscript on $1"
        echo "$output"
        exit 1
      fi
    }

    FULL_BW="${renderBooklet fullBooklet}"

    # Copy output Postscript into place
    ghostscriptTest "$FULL_BW"

    mkdir "$out"
    cd "$out"
    cp "$FULL_BW" SSS32.ps
    # Patch to include version
    sed -i 's/(revision \(.*\))/(revision \1${shortId})/' ./SSS32.ps
    # Produce PDF, if requested.
    ${lib.optionalString doPdfGeneration "ps2pdf -dPDFSETTINGS=/prepress SSS32.ps"}
  '';

  checkPhase = toString
    (map
      (page: "ghostscriptTest ${checkSinglePage page}")
      fullBooklet.pages
    ) + ''
    ghostscriptTest "$FULL_BW"
    ${lib.optionalString doOutputDiff "diff -C 5 ${src}/SSS32.ps SSS32.ps"}
  '';
}
