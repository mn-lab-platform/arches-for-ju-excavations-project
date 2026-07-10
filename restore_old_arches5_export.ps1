<#
Restores an Arches 5 package-style export into the local Arches 8 Docker stack.

Expected export layout under -ExportDir:
  graphs\*.json
  business\*.json
  concept_schemes.xml
  collections.xml
  uploadedfiles.tar.gz OR uploadedfiles\... OR files_snapshot\uploadedfiles\...

This script is intentionally split into commented steps. The comments explain
why each migration fix exists, because Arches 5 exports are not directly
compatible with Arches 8 in a few small but important places.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ExportDir,

    # Docker compose directory. By default this is the directory containing this script.
    [string]$ComposeDir = "",

    # Container/database names used by this compose project.
    [string]$AppContainer = "arches",
    [string]$DbContainer = "arches_db",
    [string]$DbName = "arches_slocal",

    # Local ../arches_data is mounted in containers as /arches_data.
    [string]$ContainerImportRoot = "/arches_data/imports",

    # In this project uploaded files live in a Docker named volume mounted here.
    [string]$MediaRootInContainer = "/arches_app/arches_slocal/arches_slocal",

    # Use this for a full clean restore. It deletes Docker volumes for this compose project.
    [switch]$ResetDockerVolumes,

    # Useful switches while debugging individual stages.
    [switch]$SkipPrepareJson,
    [switch]$SkipGraphImport,
    [switch]$SkipReferenceDataImport,
    [switch]$SkipBusinessDataImport,
    [switch]$SkipUploadedFiles,
    [switch]$SkipPostImportSqlFixes,
    [switch]$SkipReindex,
    [switch]$SkipFinalChecks,
    [switch]$SkipDbBackup
)

$ErrorActionPreference = "Stop"

function Write-Step($Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Info($Message) {
    Write-Host "    $Message"
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    Write-Info $Description
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Description"
    }
}

function Get-Utf8NoBomEncoding {
    return New-Object System.Text.UTF8Encoding($false)
}

function Read-JsonFile($Path) {
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Write-JsonFile($Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($Path, $json, (Get-Utf8NoBomEncoding))
}

function ConvertTo-Slug($Text, $Fallback) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        $Text = $Fallback
    }

    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $chars = New-Object System.Text.StringBuilder
    foreach ($ch in $normalized.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$chars.Append($ch)
        }
    }

    $slug = $chars.ToString().ToLowerInvariant()
    $slug = [regex]::Replace($slug, "[^a-z0-9]+", "_")
    $slug = $slug.Trim("_")
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "imported_graph"
    }
    return $slug
}

function Get-LocalizedText($Value, $Fallback) {
    if ($null -eq $Value) {
        return $Fallback
    }
    if ($Value -is [string]) {
        return $Value
    }
    if ($Value.PSObject.Properties.Name -contains "en") {
        return [string]$Value.en
    }
    $first = $Value.PSObject.Properties | Select-Object -First 1
    if ($first) {
        return [string]$first.Value
    }
    return $Fallback
}

function Get-GraphObjects($GraphFileJson) {
    if ($null -eq $GraphFileJson.graph) {
        return @()
    }
    return @($GraphFileJson.graph)
}

function Get-WidgetScore($Widget, $Node) {
    # Arches 8 enforces a unique widget per node in cards_x_nodes_x_widgets.
    # Some Arches 5 graphs have duplicate widgets on the same node. We keep
    # the widget that best matches the node datatype.
    $widgetId = [string]$Widget.widget_id
    $datatype = [string]$Node.datatype
    $score = 0

    if ($datatype -in @("concept", "concept-list", "semantic") -and $widgetId -eq "10000000-0000-0000-0000-000000000002") {
        $score += 100
    }
    if ($datatype -in @("domain-value", "domain-value-list") -and $widgetId -eq "10000000-0000-0000-0000-000000000015") {
        $score += 100
    }
    if ($null -ne $Widget.sortorder) {
        $score += [Math]::Max(0, 50 - [int]$Widget.sortorder)
    }

    return $score
}

function New-GraphIndexAndPreparedGraphs {
    param(
        [string]$SourceGraphsDir,
        [string]$PreparedGraphsDir
    )

    # Step: prepare graph JSON files.
    # Why: Arches 8 is stricter than Arches 5. It needs non-empty slugs,
    # UTF-8 without BOM, and no duplicate widget assignments per node.
    Write-Step "Preparing graph JSON"

    $graphIndex = @{}
    New-Item -ItemType Directory -Force $PreparedGraphsDir | Out-Null

    $graphFiles = Get-ChildItem -LiteralPath $SourceGraphsDir -Filter "*.json" -File | Sort-Object Name
    foreach ($file in $graphFiles) {
        $json = Read-JsonFile $file.FullName

        foreach ($graph in (Get-GraphObjects $json)) {
            $graphName = Get-LocalizedText $graph.name $file.BaseName

            if ([string]::IsNullOrWhiteSpace([string]$graph.slug)) {
                $graph.slug = ConvertTo-Slug $graphName $file.BaseName
                Write-Info "slug set: $($file.Name) -> $($graph.slug)"
            }

            $nodesById = @{}
            foreach ($node in @($graph.nodes)) {
                $nodesById[[string]$node.nodeid] = $node
            }

            if ($graph.PSObject.Properties.Name -contains "cards_x_nodes_x_widgets" -and $graph.cards_x_nodes_x_widgets) {
                $widgets = @($graph.cards_x_nodes_x_widgets)
                $newWidgets = New-Object System.Collections.Generic.List[object]

                $widgets | Group-Object { [string]$_.node_id } | ForEach-Object {
                    $group = @($_.Group)
                    if ($group.Count -eq 1) {
                        $newWidgets.Add($group[0])
                    }
                    else {
                        $nodeId = [string]$group[0].node_id
                        $node = $nodesById[$nodeId]
                        $keep = $group |
                            Sort-Object @{ Expression = { Get-WidgetScore $_ $node }; Descending = $true },
                                        @{ Expression = { [int]($_.sortorder) }; Descending = $false } |
                            Select-Object -First 1

                        $newWidgets.Add($keep)
                        Write-Info "dedup widget: $($file.Name), node $nodeId, kept $($keep.id)"
                    }
                }

                $graph.cards_x_nodes_x_widgets = $newWidgets.ToArray()
            }

            if ($graph.graphid) {
                $nodeIds = New-Object "System.Collections.Generic.HashSet[string]"
                $nodegroupIds = New-Object "System.Collections.Generic.HashSet[string]"

                foreach ($node in @($graph.nodes)) {
                    [void]$nodeIds.Add([string]$node.nodeid)
                    if ($node.nodegroup_id) {
                        [void]$nodegroupIds.Add([string]$node.nodegroup_id)
                    }
                }
                foreach ($nodegroup in @($graph.nodegroups)) {
                    if ($nodegroup.nodegroupid) {
                        [void]$nodegroupIds.Add([string]$nodegroup.nodegroupid)
                    }
                }

                $graphIndex[[string]$graph.graphid] = [pscustomobject]@{
                    Name = $graphName
                    NodeIds = $nodeIds
                    NodegroupIds = $nodegroupIds
                }
            }
        }

        Write-JsonFile (Join-Path $PreparedGraphsDir $file.Name) $json
    }

    return $graphIndex
}

function New-PreparedBusinessData {
    param(
        [string]$SourceBusinessDir,
        [string]$PreparedBusinessDir,
        [hashtable]$GraphIndex
    )

    # Step: prepare business JSON files.
    # Why: the old export contained a few tiles attached to the wrong graph.
    # Arches 8 crashes with StopIteration when a tile references a node that
    # does not exist in that resource model. We remove only those cross-graph
    # tiles, not whole resources.
    Write-Step "Preparing business JSON"

    New-Item -ItemType Directory -Force $PreparedBusinessDir | Out-Null

    $businessFiles = Get-ChildItem -LiteralPath $SourceBusinessDir -Filter "*.json" -File |
        Where-Object { $_.Name -notlike "*.before_*" } |
        Sort-Object Name

    foreach ($file in $businessFiles) {
        $json = Read-JsonFile $file.FullName
        $removed = 0

        foreach ($resource in @($json.business_data.resources)) {
            $graphId = [string]$resource.resourceinstance.graph_id
            if (-not $GraphIndex.ContainsKey($graphId)) {
                Write-Info "warning: unknown graph id $graphId in $($file.Name)"
                continue
            }

            $allowed = $GraphIndex[$graphId]
            $keptTiles = New-Object System.Collections.Generic.List[object]

            foreach ($tile in @($resource.tiles)) {
                $bad = $false
                $nodegroupId = [string]$tile.nodegroup_id

                if ($nodegroupId -and -not $allowed.NodegroupIds.Contains($nodegroupId)) {
                    $bad = $true
                }

                if ($tile.data) {
                    foreach ($prop in $tile.data.PSObject.Properties) {
                        if (-not $allowed.NodeIds.Contains([string]$prop.Name)) {
                            $bad = $true
                            break
                        }
                    }
                }

                if ($bad) {
                    $removed += 1
                    Write-Info "removed cross-graph tile: $($file.Name), resource $($resource.resourceinstance.resourceinstanceid), tile $($tile.tileid)"
                }
                else {
                    $keptTiles.Add($tile)
                }
            }

            $resource.tiles = $keptTiles.ToArray()
        }

        Write-JsonFile (Join-Path $PreparedBusinessDir $file.Name) $json
        if ($removed -gt 0) {
            Write-Info "removed $removed bad tile(s) from $($file.Name)"
        }
    }
}

function Invoke-Psql($Sql, $Description) {
    Invoke-Checked -Description $Description -Command {
        docker exec $DbContainer psql -h /var/run/postgresql -U postgres -d $DbName -v ON_ERROR_STOP=1 -c $Sql
    }
}

function Get-PsqlScalar($Sql) {
    $out = docker exec $DbContainer psql -h /var/run/postgresql -U postgres -d $DbName -t -A -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "psql scalar query failed"
    }
    return ($out | Select-Object -Last 1).Trim()
}

function Wait-ForDockerServices {
    # Step: wait after docker compose up.
    # Why: containers may be "started" before Postgres and Django are ready to
    # accept management commands.
    Write-Step "Waiting for Docker services"

    $dbReady = $false
    for ($i = 1; $i -le 60; $i++) {
        docker exec $DbContainer pg_isready -h /var/run/postgresql -U postgres *> $null
        if ($LASTEXITCODE -eq 0) {
            $dbReady = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $dbReady) {
        throw "Database container did not become ready"
    }

    $appReady = $false
    for ($i = 1; $i -le 60; $i++) {
        docker exec $AppContainer python manage.py arches_version *> $null
        if ($LASTEXITCODE -eq 0) {
            $appReady = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $appReady) {
        throw "Arches container did not become ready"
    }
}

function Backup-Database($BackupRoot) {
    # Step: database backup before direct SQL compatibility fixes.
    # Why: import commands are official Arches operations, but the string and
    # descriptor repairs are direct SQL migrations. This gives us a rollback
    # point after data import and before those fixes.
    if ($SkipDbBackup) {
        Write-Info "database backup skipped"
        return
    }

    Write-Step "Creating database backup before SQL fixes"

    New-Item -ItemType Directory -Force $BackupRoot | Out-Null
    $dumpName = "arches_slocal_before_post_import_fixes_$(Get-Date -Format yyyyMMdd_HHmmss).dump"
    $containerPath = "/tmp/$dumpName"
    $hostPath = Join-Path $BackupRoot $dumpName

    Invoke-Checked -Description "pg_dump in container" -Command {
        docker exec $DbContainer pg_dump -h /var/run/postgresql -U postgres -d $DbName -Fc -f $containerPath
    }
    Invoke-Checked -Description "copy dump to host" -Command {
        docker cp "${DbContainer}:$containerPath" $hostPath
    }

    Write-Info "backup: $hostPath"
}

function Import-Graphs($ContainerPreparedPath) {
    # Step: import graphs first.
    # Why: business data can only be imported after the resource models exist.
    if ($SkipGraphImport) {
        Write-Info "graph import skipped"
        return
    }

    Write-Step "Importing graphs"
    Invoke-Checked -Description "import graph JSON files" -Command {
        docker exec $AppContainer python manage.py packages -o import_graphs -s "$ContainerPreparedPath/graphs"
    }

    # Step: publish graphs.
    # Why: reports and resource APIs need PublishedGraph rows. Without this,
    # Arches may throw PublishedGraph.DoesNotExist.
    Invoke-Checked -Description "publish imported graphs" -Command {
        docker exec $AppContainer python manage.py graph publish -u admin -ui
    }
}

function Import-ReferenceData($ContainerRawExportPath) {
    # Step: import RDM/reference data before business data.
    # Why: concept and concept-list tiles store value UUIDs. Those UUIDs must
    # exist in the values/concepts tables before indexing works.
    if ($SkipReferenceDataImport) {
        Write-Info "reference data import skipped"
        return
    }

    Write-Step "Importing reference data"
    foreach ($fileName in @("concept_schemes.xml", "collections.xml")) {
        $hostFile = Join-Path $ExportDir $fileName
        if (Test-Path -LiteralPath $hostFile) {
            Invoke-Checked -Description "import $fileName" -Command {
                docker exec $AppContainer python manage.py packages -o import_reference_data -s "$ContainerRawExportPath/$fileName" -ow overwrite -st keep -pi
            }
        }
        else {
            Write-Info "warning: missing $fileName in export"
        }
    }
}

function Import-BusinessData($ContainerPreparedPath) {
    # Step: import resources with indexing disabled.
    # Why: Arches 5 string/concept formats need compatibility fixes before
    # Elasticsearch indexing can run cleanly.
    if ($SkipBusinessDataImport) {
        Write-Info "business data import skipped"
        return
    }

    Write-Step "Importing business data"
    $businessFiles = Get-ChildItem -LiteralPath (Join-Path $PreparedRoot "business") -Filter "*.json" -File | Sort-Object Name
    foreach ($file in $businessFiles) {
        Invoke-Checked -Description "import $($file.Name)" -Command {
            docker exec $AppContainer python manage.py packages -o import_business_data -s "$ContainerPreparedPath/business/$($file.Name)" -ow true -pi
        }
    }
}

function Import-UploadedFiles($ContainerRawExportPath) {
    # Step: copy uploaded files into the Docker named volume.
    # Why: ../arches_data is mounted as /arches_data, but uploadedfiles is a
    # separate named volume mounted over the project folder. Copying to the
    # Windows project path does not make files visible to Arches.
    if ($SkipUploadedFiles) {
        Write-Info "uploaded files import skipped"
        return
    }

    Write-Step "Importing uploaded files"

    $target = "$MediaRootInContainer/uploadedfiles"
    Invoke-Checked -Description "ensure uploadedfiles target directory" -Command {
        docker exec $AppContainer sh -c "mkdir -p '$target'"
    }

    if (Test-Path -LiteralPath (Join-Path $ExportDir "uploadedfiles.tar.gz")) {
        Invoke-Checked -Description "extract uploadedfiles.tar.gz into media root" -Command {
            docker exec $AppContainer sh -c "tar -xzf '$ContainerRawExportPath/uploadedfiles.tar.gz' -C '$MediaRootInContainer'"
        }
    }
    elseif (Test-Path -LiteralPath (Join-Path $ExportDir "files_snapshot\uploadedfiles")) {
        Invoke-Checked -Description "copy files_snapshot/uploadedfiles into Docker volume" -Command {
            docker exec $AppContainer sh -c "cp -an '$ContainerRawExportPath/files_snapshot/uploadedfiles/.' '$target/'"
        }
    }
    elseif (Test-Path -LiteralPath (Join-Path $ExportDir "uploadedfiles\uploadedfiles")) {
        Invoke-Checked -Description "copy nested uploadedfiles/uploadedfiles into Docker volume" -Command {
            docker exec $AppContainer sh -c "cp -an '$ContainerRawExportPath/uploadedfiles/uploadedfiles/.' '$target/'"
        }
    }
    elseif (Test-Path -LiteralPath (Join-Path $ExportDir "uploadedfiles")) {
        Invoke-Checked -Description "copy uploadedfiles directory into Docker volume" -Command {
            docker exec $AppContainer sh -c "cp -an '$ContainerRawExportPath/uploadedfiles/.' '$target/'"
        }
    }
    else {
        Write-Info "warning: no uploaded files found in export"
    }

    docker exec $AppContainer sh -c "du -sh '$target' || true"
    docker exec $AppContainer sh -c "find '$target' -type f | wc -l || true"
}

function Fix-StringTileData {
    # Step: convert Arches 5 strings to Arches 8 multilingual string objects.
    # Why: Arches 5 stores string node values as plain JSON strings. Arches 8
    # indexing expects {"en": {"value": "...", "direction": "ltr"}}.
    Write-Step "Fixing string tile values"

    $sql = @"
WITH string_nodes AS (
  SELECT nodeid::text AS nodeid
  FROM nodes
  WHERE datatype = 'string'
),
to_fix AS (
  SELECT
    t.tileid,
    jsonb_object_agg(
      e.key,
      CASE
        WHEN sn.nodeid IS NOT NULL AND jsonb_typeof(e.value) = 'string'
        THEN jsonb_build_object(
          'en',
          jsonb_build_object(
            'value', e.value #>> '{}',
            'direction', 'ltr'
          )
        )
        ELSE e.value
      END
    ) AS new_tiledata
  FROM tiles t
  CROSS JOIN LATERAL jsonb_each(t.tiledata) e
  LEFT JOIN string_nodes sn ON sn.nodeid = e.key
  WHERE EXISTS (
    SELECT 1
    FROM jsonb_each(t.tiledata) e2
    JOIN string_nodes sn2 ON sn2.nodeid = e2.key
    WHERE jsonb_typeof(e2.value) = 'string'
  )
  GROUP BY t.tileid
)
UPDATE tiles t
SET tiledata = to_fix.new_tiledata
FROM to_fix
WHERE t.tileid = to_fix.tileid;
"@
    Invoke-Psql $sql "convert string tiledata"

    $remaining = Get-PsqlScalar "SELECT COUNT(*) FROM tiles t JOIN LATERAL jsonb_each(t.tiledata) e ON true JOIN nodes n ON n.nodeid::text = e.key WHERE n.datatype = 'string' AND jsonb_typeof(e.value) = 'string';"
    if ([int]$remaining -ne 0) {
        throw "String fix incomplete. Remaining bad string values: $remaining"
    }
    Write-Info "bad string values: 0"
}

function Fix-DescriptorConfig {
    # Step: migrate descriptor function config from Arches 5 shape to Arches 8 shape.
    # Why: old exports have config.name/config.description/config.map_popup, while
    # Arches 8 reads config.descriptor_types.name/description/map_popup.
    Write-Step "Fixing descriptor function config"

    $sql = @"
UPDATE functions_x_graphs fxg
SET config = jsonb_set(
  jsonb_set(
    jsonb_set(
      config,
      '{descriptor_types,name}',
      config->'name',
      true
    ),
    '{descriptor_types,description}',
    config->'description',
    true
  ),
  '{descriptor_types,map_popup}',
  config->'map_popup',
  true
)
FROM functions f
WHERE f.functionid = fxg.functionid
  AND f.functiontype = 'primarydescriptors'
  AND config ? 'name'
  AND config ? 'description'
  AND config ? 'map_popup';
"@
    Invoke-Psql $sql "migrate descriptor config"
}

function Assert-NoMissingConceptValues {
    # Step: verify RDM completeness before reindexing.
    # Why: if business data points to value UUIDs missing from the values table,
    # reindexing fails with "Value has no concept".
    Write-Step "Checking missing concept values"

    $sql = @"
WITH concept_values AS (
  SELECT t.tileid, t.resourceinstanceid, n.nodeid, n.name AS node_name, n.datatype, g.name AS graph_name, t.tiledata ->> n.nodeid::text AS valueid
  FROM tiles t
  JOIN nodes n ON t.tiledata ? n.nodeid::text
  JOIN graphs g ON g.graphid = n.graphid
  WHERE n.datatype = 'concept'
    AND NULLIF(t.tiledata ->> n.nodeid::text, '') IS NOT NULL
  UNION ALL
  SELECT t.tileid, t.resourceinstanceid, n.nodeid, n.name AS node_name, n.datatype, g.name AS graph_name, elem.value AS valueid
  FROM tiles t
  JOIN nodes n ON t.tiledata ? n.nodeid::text
  JOIN graphs g ON g.graphid = n.graphid
  CROSS JOIN LATERAL jsonb_array_elements_text(t.tiledata -> n.nodeid::text) AS elem(value)
  WHERE n.datatype = 'concept-list'
    AND jsonb_typeof(t.tiledata -> n.nodeid::text) = 'array'
    AND NULLIF(elem.value, '') IS NOT NULL
)
SELECT COUNT(*)
FROM concept_values cv
LEFT JOIN values v ON v.valueid::text = cv.valueid
WHERE v.valueid IS NULL;
"@

    $missing = Get-PsqlScalar $sql
    Write-Info "missing concept values: $missing"
    if ([int]$missing -ne 0) {
        throw "Missing concept values remain. Check concept_schemes.xml and collections.xml."
    }
}

function Run-PostImportSqlFixes($BackupRoot) {
    if ($SkipPostImportSqlFixes) {
        Write-Info "post-import SQL fixes skipped"
        return
    }

    Backup-Database $BackupRoot
    Fix-StringTileData
    Fix-DescriptorConfig
    Assert-NoMissingConceptValues
}

function Reindex-Database {
    # Step: reindex after all compatibility fixes.
    # Why: business data was imported with -pi to avoid indexing old Arches 5
    # data shapes. Now descriptors and Elasticsearch can be rebuilt safely.
    if ($SkipReindex) {
        Write-Info "reindex skipped"
        return
    }

    Write-Step "Reindexing database"
    Invoke-Checked -Description "es reindex_database with descriptor recalculation" -Command {
        docker exec $AppContainer python manage.py es reindex_database -b 100 -rd --traceback -v 2
    }
}

function Show-FinalChecks {
    # Step: print quick sanity checks.
    # Why: these are the same checks we used manually: resource counts and how
    # many names still show as Undefined.
    if ($SkipFinalChecks) {
        Write-Info "final checks skipped"
        return
    }

    Write-Step "Resource counts"
    Invoke-Checked -Description "print resource counts" -Command {
        docker exec $DbContainer psql -h /var/run/postgresql -U postgres -d $DbName -c "SELECT g.name, COUNT(ri.resourceinstanceid) FROM resource_instances ri JOIN graphs g ON g.graphid = ri.graphid GROUP BY g.name ORDER BY COUNT(*) DESC;"
    }

    Write-Step "Undefined descriptor names"
    Invoke-Checked -Description "print undefined descriptor counts" -Command {
        docker exec $DbContainer psql -h /var/run/postgresql -U postgres -d $DbName -c "SELECT g.name, COUNT(*) FILTER (WHERE ri.name->>'en' = 'Undefined') AS undefined_names, COUNT(*) AS total FROM resource_instances ri JOIN graphs g ON g.graphid = ri.graphid GROUP BY g.name ORDER BY undefined_names DESC;"
    }
}

# Step: resolve paths once at the start.
# Why: later Docker paths are derived from the host export folder name.
$ExportDir = (Resolve-Path -LiteralPath $ExportDir).Path
if ([string]::IsNullOrWhiteSpace($ComposeDir)) {
    if ($PSCommandPath) {
        $ComposeDir = Split-Path -Parent $PSCommandPath
    }
    else {
        $ComposeDir = (Get-Location).Path
    }
}
$ComposeDir = (Resolve-Path -LiteralPath $ComposeDir).Path

$exportName = Split-Path -Leaf $ExportDir
$containerRawExportPath = "$ContainerImportRoot/$exportName"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PreparedRoot = Join-Path $ExportDir ".restore_prepared_$timestamp"
$containerPreparedPath = "$containerRawExportPath/.restore_prepared_$timestamp"
$backupRoot = Join-Path $ExportDir ".restore_backups\$timestamp"

Write-Step "Arches 5 export restore into local Arches 8 Docker"
Write-Info "host export:      $ExportDir"
Write-Info "container export: $containerRawExportPath"
Write-Info "prepared copy:    $PreparedRoot"
Write-Info "compose dir:      $ComposeDir"

if (-not (Test-Path -LiteralPath (Join-Path $ExportDir "graphs"))) {
    throw "Missing graphs directory under export"
}
if (-not (Test-Path -LiteralPath (Join-Path $ExportDir "business"))) {
    throw "Missing business directory under export"
}

if (-not $SkipPrepareJson) {
    # Step: make prepared JSON copies instead of modifying raw export files.
    # Why: the raw export stays untouched and can always be compared/reused.
    New-Item -ItemType Directory -Force $PreparedRoot | Out-Null
    $graphIndex = New-GraphIndexAndPreparedGraphs `
        -SourceGraphsDir (Join-Path $ExportDir "graphs") `
        -PreparedGraphsDir (Join-Path $PreparedRoot "graphs")

    New-PreparedBusinessData `
        -SourceBusinessDir (Join-Path $ExportDir "business") `
        -PreparedBusinessDir (Join-Path $PreparedRoot "business") `
        -GraphIndex $graphIndex
}

Push-Location $ComposeDir
try {
    if ($ResetDockerVolumes) {
        # Step: reset the local Docker stack for a clean restore.
        # Why: imports into a dirty Arches DB can leave duplicates or partial data.
        Write-Step "Resetting Docker volumes"
        Invoke-Checked -Description "docker compose down -v" -Command { docker compose down -v }
        Invoke-Checked -Description "docker compose up -d" -Command { docker compose up -d }
        Wait-ForDockerServices
    }

    Import-Graphs $containerPreparedPath
    Import-ReferenceData $containerRawExportPath
    Import-BusinessData $containerPreparedPath
    Import-UploadedFiles $containerRawExportPath
    Run-PostImportSqlFixes $backupRoot
    Reindex-Database
    Show-FinalChecks
}
finally {
    Pop-Location
}

Write-Step "Restore finished"
