param(
    [string]$InputPath = "e:\AAA工作\大三\下学期学校\金相大会\code\question_bank_raw_lines.txt",
    [string]$OutputPath = "e:\AAA工作\大三\下学期学校\金相大会\code\data\question_bank.cleaned.json",
    [string]$ReportPath = "e:\AAA工作\大三\下学期学校\金相大会\code\data\clean_report.txt"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input file not found: $InputPath"
}

$rawLines = Get-Content -LiteralPath $InputPath
$lines = New-Object System.Collections.Generic.List[string]
foreach ($line in $rawLines) {
    $trimmed = ($line -replace "\s+", " ").Trim()
    if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
        [void]$lines.Add($trimmed)
    }
}

# Normalize some common OCR variants before parsing.
function Normalize-Line([string]$text) {
    $t = $text
    $t = $t -replace "^\.+\s*(\d+)", '$1'
    $t = $t -replace "^\s*(\d+)\s+、", '$1、'
    $t = $t -replace "^\s*(\d+)\s+\.\s*", '$1.'
    $t = $t -replace "^\s*答案\s*[：:]\s*", '答案：'
    $t = $t -replace "\s+", ' '
    return $t.Trim()
}

function Split-OptionLine([string]$line) {
    $normalized = $line -replace '([A-DＡ-Ｄ])\s*[\.．、:：)]\s*', '$1. '
    $pattern = '(?<![A-Z])([A-D])\.\s*([^A-D]*?)(?=\s+[A-D]\.\s*|$)'
    $matches = [regex]::Matches($normalized, $pattern)
    $result = @()
    foreach ($m in $matches) {
        $label = $m.Groups[1].Value
        $content = ($m.Groups[2].Value).Trim(' ', '。', ';', '；')
        if ($content) {
            $result += [PSCustomObject]@{ label = $label; text = $content }
        }
    }
    return $result
}

$normalizedLines = $lines | ForEach-Object { Normalize-Line $_ }

$headerRegex = '^\s*(\d+)\s*[、\.．]\s*(.+)$'
$answerRegex = '^答案：\s*([A-D]+)\s*$'

$blocks = @()
$current = $null

foreach ($line in $normalizedLines) {
    if ($line -match $headerRegex) {
        if ($null -ne $current) {
            $blocks += $current
        }
        $current = [PSCustomObject]@{
            original_no = [int]$Matches[1]
            title = $Matches[2].Trim()
            body = New-Object System.Collections.Generic.List[string]
        }
        continue
    }

    if ($null -ne $current) {
        [void]$current.body.Add($line)
    }
}

if ($null -ne $current) {
    $blocks += $current
}

$questions = @()
$issues = New-Object System.Collections.Generic.List[string]
$index = 0

foreach ($b in $blocks) {
    $index++
    $questionText = $b.title
    $optionsMap = @{}
    $answer = ""
    $explanationParts = New-Object System.Collections.Generic.List[string]

    $pendingOptionLabel = $null

    foreach ($line in $b.body) {
        if ($line -match $answerRegex) {
            $answer = $Matches[1]
            continue
        }

        if ($line -match '^解析[：:]\s*(.*)$') {
            [void]$explanationParts.Add($Matches[1].Trim())
            continue
        }

        $splitOpts = Split-OptionLine $line
        if ($splitOpts.Count -gt 0) {
            foreach ($o in $splitOpts) {
                $optionsMap[$o.label] = $o.text
                $pendingOptionLabel = $o.label
            }
            continue
        }

        if ($pendingOptionLabel -and $line -notmatch '^答案[：:]') {
            $optionsMap[$pendingOptionLabel] = ($optionsMap[$pendingOptionLabel] + " " + $line).Trim()
            continue
        }

        if ($optionsMap.Count -eq 0) {
            $questionText = ($questionText + " " + $line).Trim()
        } else {
            [void]$explanationParts.Add($line)
        }
    }

    $optionList = @()
    foreach ($k in @('A','B','C','D')) {
        if ($optionsMap.ContainsKey($k)) {
            $optionList += [PSCustomObject]@{ key = $k; text = $optionsMap[$k] }
        }
    }

    if ($optionList.Count -lt 2) {
        [void]$issues.Add("Q$index options_lt_2 original_no=$($b.original_no)")
    }

    if (-not $answer) {
        [void]$issues.Add("Q$index no_answer original_no=$($b.original_no)")
    } elseif ($answer -notmatch '^[A-D]+$') {
        [void]$issues.Add("Q$index invalid_answer=$answer original_no=$($b.original_no)")
    }

    $questions += [PSCustomObject]@{
        id = $index
        original_no = $b.original_no
        type = if ($answer.Length -gt 1) { 'multiple' } else { 'single' }
        question = $questionText
        options = $optionList
        answer = $answer
        explanation = (($explanationParts -join ' ').Trim())
    }
}

$payload = [PSCustomObject]@{
    meta = [PSCustomObject]@{
        source = "金相大会题库.docx"
        cleaned_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        total = $questions.Count
        issue_count = $issues.Count
    }
    questions = $questions
}

$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

$report = @()
$report += "total_questions=$($questions.Count)"
$report += "issues=$($issues.Count)"
$report += ""
$report += "top_issues:"
if ($issues.Count -eq 0) {
    $report += "none"
} else {
    $report += ($issues | Select-Object -First 100)
}

Set-Content -LiteralPath $ReportPath -Value $report -Encoding UTF8

Write-Output "Cleaned questions: $($questions.Count)"
Write-Output "Issue count: $($issues.Count)"
Write-Output "JSON: $OutputPath"
Write-Output "Report: $ReportPath"
