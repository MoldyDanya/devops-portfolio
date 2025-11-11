const core = require('@actions/core');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function getUnityVersion() {
  try {
    const projectVersionPath = 'ProjectSettings/ProjectVersion.txt';
    if (!fs.existsSync(projectVersionPath)) {
      core.warning('ProjectVersion.txt not found, using default version');
      return 'unknown';
    }
    
    const content = fs.readFileSync(projectVersionPath, 'utf8');
    const match = content.match(/m_EditorVersion:\s*(.+)/);
    
    if (!match) {
      core.warning('Could not parse Unity version from ProjectVersion.txt');
      return 'unknown';
    }
    
    // Convert version to safe filename format: 2022.3.45f1 -> 2022-3-45f1
    const version = match[1].trim().replace(/\./g, '-');
    core.info(`Detected Unity version: ${match[1].trim()}`);
    return version;
  } catch (error) {
    core.warning(`Failed to read Unity version: ${error.message}`);
    return 'unknown';
  }
}

async function cleanupOldCaches(cacheDir, repository, platform, unityVersion, maxCaches = 20, maxAgeDays = 14) {
  try {
    const files = fs.readdirSync(cacheDir);
    const platformUpper = platform.toUpperCase();
    const cacheFiles = files
      .filter(file => file.includes(`-${unityVersion}-${platformUpper}.tzst`))
      .map(file => {
        const filePath = path.join(cacheDir, file);
        const stats = fs.statSync(filePath);
        return {
          path: filePath,
          name: file,
          mtime: stats.mtime,
          age: (Date.now() - stats.mtime.getTime()) / (1000 * 60 * 60 * 24)
        };
      })
      .sort((a, b) => b.mtime - a.mtime);

    let deletedCount = 0;
    
    // Delete files older than maxAgeDays
    for (const file of cacheFiles) {
      if (file.age > maxAgeDays) {
        fs.unlinkSync(file.path);
        core.info(`Deleted old cache (${Math.round(file.age)} days): ${file.name}`);
        deletedCount++;
      }
    }
    
    // Keep only maxCaches newest files
    const remainingFiles = cacheFiles.filter(file => file.age <= maxAgeDays);
    if (remainingFiles.length > maxCaches) {
      const filesToDelete = remainingFiles.slice(maxCaches);
      for (const file of filesToDelete) {
        fs.unlinkSync(file.path);
        core.info(`Deleted excess cache: ${file.name}`);
        deletedCount++;
      }
    }
    
    if (deletedCount > 0) {
      core.info(`Cleanup completed: ${deletedCount} cache files deleted`);
    }
  } catch (error) {
    core.warning(`Cache cleanup failed: ${error.message}`);
  }
}

async function restoreCache(cacheFile) {
  const stats = fs.statSync(cacheFile);
  const sizeFormatted = formatBytes(stats.size);
  core.info(`Cache found: ${cacheFile} (${sizeFormatted})`);
  
  // Restore cache
  fs.mkdirSync('Library', { recursive: true });
  await new Promise((resolve, reject) => {
    exec(`tar --use-compress-program="zstd -6 -T0" -xf "${cacheFile}" -C ./`, (error, stdout, stderr) => {
      if (error) {
        reject(error);
      } else {
        core.info(`Cache restored successfully (${sizeFormatted})`);
        resolve();
      }
    });
  });
  
  // Fix permissions
  const username = process.env.USER || 'runner';
  await new Promise((resolve) => {
    exec(`sudo chown -R ${username}:${username} Library`, (error) => {
      if (error) {
        core.warning(`Failed to change permissions: ${error.message}`);
      }
      resolve();
    });
  });
}

async function run() {
  try {
    const platform = core.getInput('platform', { required: true });
    const repository = core.getInput('repository', { required: true });
    const branch = core.getInput('branch') || 'master';
    const runnerUsername = core.getInput('runner_username') || 'runner';
    const cacheBasePath = core.getInput('cache_base_path') || `/home/${runnerUsername}/actions-cache`;
    const maxCaches = parseInt(core.getInput('max_caches'));
    const maxAgeDays = parseInt(core.getInput('max_age_days'));
    const cleanBuild = core.getInput('clean_build') === 'true';
    
    const platformUpper = platform.toUpperCase();
    const branchSafe = branch.replace(/\//g, '-');
    const unityVersion = getUnityVersion();
    const cacheDir = path.join(cacheBasePath, repository);
    
    // Cache files to try in priority order with Unity version
    const cacheFiles = [path.join(cacheDir, `Library-${branchSafe}-${unityVersion}-${platformUpper}.tzst`)];
    
    // Add master fallback only if current branch is not master
    if (branchSafe !== 'master') {
      cacheFiles.push(path.join(cacheDir, `Library-master-${unityVersion}-${platformUpper}.tzst`));
    }
    
    // Save paths and config to environment for post step
    core.exportVariable('CACHE_PATH_SAVE', cacheFiles[0]); // Always save to current branch
    core.exportVariable('SKIP_SAVE', core.getInput('skip-save') || 'false');
    
    // Ensure cache directory exists
    fs.mkdirSync(cacheDir, { recursive: true });
    
    // Run cleanup
    await cleanupOldCaches(cacheDir, repository, platform, unityVersion, maxCaches, maxAgeDays);
    
    // Check if clean build is requested
    if (cleanBuild) {
      core.info('Clean build requested - skipping cache restore');
      core.setOutput('cache-hit', 'false');
      return;
    }
    
    // Try to restore cache with fallback logic
    let cacheRestored = false;
    for (let i = 0; i < cacheFiles.length; i++) {
      const cacheFile = cacheFiles[i];
      if (fs.existsSync(cacheFile)) {
        const isCurrentBranch = i === 0;
        const cacheSource = isCurrentBranch ? 'current branch' : 'master fallback';
        
        core.info(`Using cache from ${cacheSource}`);
        core.setOutput('cache-hit', isCurrentBranch ? 'true' : 'fallback');
        
        await restoreCache(cacheFile);
        cacheRestored = true;
        break;
      }
    }
    
    if (!cacheRestored) {
      core.info(`No cache found for ${branchSafe} or master - clean build`);
      core.setOutput('cache-hit', 'false');
    }
  } catch (error) {
    core.setFailed(error.message);
  }
}

run();