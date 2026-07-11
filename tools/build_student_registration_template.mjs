import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const root = process.cwd();
const outputDir = path.join(root, "templates");
const outputPath = path.join(outputDir, "AXIOMBYTE_SMS_student_registration_import_template.xlsx");
const previewPath = path.join(root, ".codex_build", "student-template", "student_registration_template_preview.png");

await fs.mkdir(outputDir, { recursive: true });

const workbook = Workbook.create();
const sheet = workbook.worksheets.add("Student Import");
const lists = workbook.worksheets.add("Lists");

const headers = [
  "Surname",
  "First Name",
  "Other Names",
  "Ghana Card Number",
  "Gender",
  "Disability Status",
  "Date of Birth",
  "Guardian Name",
  "Relationship",
  "Phone Number",
  "Profession",
  "Residential Address",
  "Admission Year",
  "Student Level",
  "Learning Area",
  "Class",
  "Residential Status",
  "House",
  "Notes"
];

const required = [
  "Surname",
  "First Name",
  "Gender",
  "Disability Status",
  "Date of Birth",
  "Guardian Name",
  "Relationship",
  "Phone Number",
  "Admission Year",
  "Learning Area",
  "Class",
  "Residential Status"
];

sheet.showGridLines = false;
sheet.getRange("A1:S1").merge();
sheet.getRange("A1").values = [["AXIOMBYTE SMS - Student Registration Import Template"]];
sheet.getRange("A2:S2").merge();
sheet.getRange("A2").values = [[
  "Fill one student per row. Keep the headers exactly as they are. Required columns are marked in row 4."
]];
sheet.getRange("A1:S1").format = {
  fill: "#dff4d8",
  font: { bold: true, color: "#14532d", size: 15 },
  horizontalAlignment: "center"
};
sheet.getRange("A2:S2").format = {
  fill: "#f3fbef",
  font: { color: "#315a35", italic: true },
  horizontalAlignment: "center"
};

sheet.getRange("A3:S3").values = [headers];
sheet.getRange("A4:S4").values = [headers.map((header) => required.includes(header) ? "Required" : "Optional")];
sheet.getRange("A3:S3").format = {
  fill: "#2f7d32",
  font: { bold: true, color: "#ffffff" },
  wrapText: true,
  horizontalAlignment: "center"
};
sheet.getRange("A4:S4").format = {
  fill: "#eef8e8",
  font: { bold: true, color: "#2f5f33" },
  horizontalAlignment: "center"
};

const sampleRows = [
  [
    "Tettey",
    "Foster",
    "Adamnor",
    "GHA-000000000-0",
    "Male",
    "No",
    new Date("2008-03-22"),
    "Ama Tettey",
    "Mother",
    "0240000000",
    "Trader",
    "Asuom",
    2025,
    "",
    "General Science",
    "SCI_24",
    "Boarding",
    "Green House",
    ""
  ],
  [
    "Agbozo",
    "Ruby",
    "Teinokie",
    "",
    "Female",
    "No",
    new Date("2009-04-25"),
    "Kwame Agbozo",
    "Father",
    "0550000000",
    "Farmer",
    "Asuom",
    2025,
    "",
    "General Arts",
    "ART_24",
    "Day",
    "",
    ""
  ]
];

sheet.getRange("A5:S6").values = sampleRows;
sheet.getRange("N5:N104").formulasR1C1 = Array.from({ length: 100 }, () => [
  '=IF(RC[-1]="","",IF(YEAR(TODAY())-RC[-1]=0,"Year 1",IF(YEAR(TODAY())-RC[-1]=1,"Year 2",IF(YEAR(TODAY())-RC[-1]=2,"Year 3","Completed"))))'
]);

sheet.tables.add("A3:S104", true, "StudentImportTable");
sheet.freezePanes.freezeRows(4);
sheet.getRange("G5:G104").format.numberFormat = "yyyy-mm-dd";
sheet.getRange("M5:M104").format.numberFormat = "0";
sheet.getRange("A3:S104").format.borders = { preset: "all", style: "thin", color: "#d7e5d3" };
sheet.getRange("A5:S104").format = { wrapText: true, verticalAlignment: "top" };

sheet.getRange("A:A").format.columnWidth = 16;
sheet.getRange("B:B").format.columnWidth = 16;
sheet.getRange("C:C").format.columnWidth = 18;
sheet.getRange("D:D").format.columnWidth = 22;
sheet.getRange("E:F").format.columnWidth = 16;
sheet.getRange("G:G").format.columnWidth = 16;
sheet.getRange("H:H").format.columnWidth = 22;
sheet.getRange("I:I").format.columnWidth = 18;
sheet.getRange("J:J").format.columnWidth = 16;
sheet.getRange("K:L").format.columnWidth = 22;
sheet.getRange("M:N").format.columnWidth = 16;
sheet.getRange("O:P").format.columnWidth = 20;
sheet.getRange("Q:R").format.columnWidth = 18;
sheet.getRange("S:S").format.columnWidth = 22;

lists.showGridLines = false;
lists.getRange("A1:F1").values = [["Gender", "Disability Status", "Relationship", "Admission Year", "Residential Status", "Guidance"]];
lists.getRange("A1:F1").format = { fill: "#2f7d32", font: { bold: true, color: "#ffffff" } };
lists.getRange("A2:A3").values = [["Male"], ["Female"]];
lists.getRange("B2:B3").values = [["No"], ["Yes"]];
lists.getRange("C2:C5").values = [["Father"], ["Mother"], ["Guardian"], ["Other Relative"]];
lists.getRange("D2:D5").values = [[2025], [2024], [2023], [2022]];
lists.getRange("E2:E3").values = [["Boarding"], ["Day"]];
lists.getRange("F2:F8").values = [
  ["Learning Area and Class must match records created under Settings."],
  ["House is only needed for Boarding students or when your school assigns houses."],
  ["Date of Birth should remain a true Excel date, formatted yyyy-mm-dd."],
  ["Student Level is calculated from Admission Year."],
  ["Do not rename, remove, or reorder headers before upload."],
  ["Save the completed workbook as .xlsx. No CSV."],
  ["Profile photos will be uploaded later inside the student profile."]
];
lists.getRange("A1:F8").format.borders = { preset: "all", style: "thin", color: "#d7e5d3" };
lists.getRange("A:F").format.columnWidth = 24;

sheet.getRange("E5:E104").dataValidation = { rule: { type: "list", formula1: "'Lists'!$A$2:$A$3" } };
sheet.getRange("F5:F104").dataValidation = { rule: { type: "list", formula1: "'Lists'!$B$2:$B$3" } };
sheet.getRange("I5:I104").dataValidation = { rule: { type: "list", formula1: "'Lists'!$C$2:$C$5" } };
sheet.getRange("M5:M104").dataValidation = { rule: { type: "list", formula1: "'Lists'!$D$2:$D$5" } };
sheet.getRange("Q5:Q104").dataValidation = { rule: { type: "list", formula1: "'Lists'!$E$2:$E$3" } };

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 50 },
  summary: "formula error scan"
});
console.log(errors.ndjson || "formula error scan complete");

const preview = await workbook.render({ sheetName: "Student Import", range: "A1:S12", scale: 1, format: "png" });
await fs.writeFile(previewPath, new Uint8Array(await preview.arrayBuffer()));

const xlsx = await SpreadsheetFile.exportXlsx(workbook);
await xlsx.save(outputPath);
console.log(outputPath);
