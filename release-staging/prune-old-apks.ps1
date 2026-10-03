# Prune old APK assets from GitHub Releases (everything older than v2.6.0)
# Semver compare helper
function Compare-Semver($a, $b) {
  # Normalize: strip leading 'v', split on '.', compare numerically
  $a2 = ($a -replace '^v','') -split '\+' | Select-Object -First 1
  $b2 = ($b -replace '^v','') -split '\+' | Select-Object -First 1
  $pa = $a2 -split '\.' | ForEach-Object { [int]$_ }
  $pb = $b2 -split '\.' | ForEach-Object { [int]$_ }
  for ($i=0; $i -lt [Math]::Max($pa.Count,$pb.Count); $i++) {
    $va = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
    $vb = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
    if ($va -lt $vb) { return -1 }
    if ($va -gt $vb) { return 1 }
  }
  return 0
}

$targetTag = "v2.6.0"
$repos = @("NavDevs/Signal-Aid", "NavDevs/clearpath-server")

foreach ($repo in $repos) {
  Write-Output "========================================================"
  Write-Output "Processing repo: $repo"
  Write-Output "========================================================"

  # Get ALL releases for the repo
  $releasesJson = gh api "repos/$repo/releases?per_page=100" --jq '.' 2>&1 | Out-String
  $releases = $releasesJson | ConvertFrom-Json

  if (-not $releases -or $releases.Count -eq 0) {
    Write-Output "  No releases found in $repo"
    continue
  }

  $prunedCount = 0
  $keptCount = 0

  foreach ($rel in $releases) {
    $tag = $rel.tag_name
    $cmp = Compare-Semver $tag $targetTag

    if ($cmp -lt 0) {
      # Older than target → prune *.apk assets
      Write-Output "  [OLDER] tag=$tag  (prune *.apk assets, release_id=$($rel.id))"
      foreach ($asset in $rel.assets) {
        if ($asset.name -match '\.apk$') {
          Write-Output "    -> DELETE asset id=$($asset.id) name=$($asset.name)"
          $deleteResult = gh api --method DELETE "repos/$repo/releases/assets/$($asset.id)" 2>&1
          if ($LASTEXITCODE -eq 0) {
            Write-Output "       OK (deleted)"
            $prunedCount++
          } else {
            Write-Output "       FAIL: $deleteResult"
          }
        } else {
          Write-Output "    -> KEEP   id=$($asset.id) name=$($asset.name) (non-APK)"
        }
      }
    } else {
      Write-Output "  [>=v2.6.0] tag=$tag  (keep all assets)"
      foreach ($asset in $rel.assets) {
        Write-Output "    -> KEEP   id=$($asset.id) name=$($asset.name)"
        if ($asset.name -match '\.apk$') { $keptCount++ }
      }
    }
  }
  Write-Output "  --- $repo : pruned=$prunedCount APK assets  keptCurrentVer=$keptCount APK assets ---"
}

Write-Output "=== Pruning complete ==="
