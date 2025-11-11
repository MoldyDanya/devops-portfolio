const core = require('@actions/core');
const { exec } = require('child_process');
const fs = require('fs');

function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

async function run() {
  try {
    const cacheFile = process.env.CACHE_PATH_SAVE;
    const skipSave = process.env.SKIP_SAVE;
    
    if (!cacheFile) {
      core.warning('Cache path not found in environment');
      return;
    }
    
    if (skipSave === 'true') {
      core.info('Skipping cache save due to skip-save parameter');
      return;
    }
    
    if (!fs.existsSync('Library')) {
      core.info('Library folder not found, skipping cache save');
      return;
    }
    
    // Check if cache needs updating by comparing content hash
    let needsUpdate = true;
    let currentHash = '';
    
    if (fs.existsSync(cacheFile)) {
      core.info('Existing cache found, checking if update is needed...');
      
      // Generate hash of current Library folder using faster method
      await new Promise((resolve, reject) => {
        // Use find with newer/stat for faster directory comparison
        exec(`find Library -type f -printf '%T@ %s %p\\n' 2>/dev/null | sort | md5sum`, (error, stdout, stderr) => {
          if (error) {
            core.warning(`Failed to generate Library hash: ${error.message}`);
            resolve();
          } else {
            currentHash = stdout.trim().split(' ')[0];
            core.info(`Current Library hash: ${currentHash}`);
            resolve();
          }
        });
      });
      
      // Get hash of cached Library
      const hashFile = cacheFile + '.hash';
      if (fs.existsSync(hashFile)) {
        const cachedHash = fs.readFileSync(hashFile, 'utf8').trim();
        core.info(`Cached Library hash: ${cachedHash}`);
        
        if (currentHash === cachedHash) {
          needsUpdate = false;
          core.info('✅ Library unchanged, skipping cache save');
          return;
        } else {
          core.info('📝 Library changed, updating cache');
        }
      } else {
        core.info('No hash file found, cache will be updated');
      }
    }
    
    if (needsUpdate) {
      core.info(`Saving cache to: ${cacheFile}`);
      
      // Ensure directory has proper permissions
      const cacheDir = require('path').dirname(cacheFile);
      await new Promise((resolve) => {
        exec(`sudo mkdir -p "${cacheDir}" && sudo chown -R ${process.env.USER}:${process.env.USER} "${cacheDir}"`, (error) => {
          if (error) {
            core.warning(`Failed to fix directory permissions: ${error.message}`);
          }
          resolve();
        });
      });
      
      // Remove old cache
      if (fs.existsSync(cacheFile)) {
        fs.unlinkSync(cacheFile);
      }
      
      // Create new cache
      await new Promise((resolve, reject) => {
        exec(`tar --use-compress-program="zstd -6 -T0" -cf "${cacheFile}" Library`, (error, stdout, stderr) => {
          if (error) {
            reject(error);
          } else {
            // Check cache file size after creation
            if (fs.existsSync(cacheFile)) {
              const stats = fs.statSync(cacheFile);
              const sizeFormatted = formatBytes(stats.size);
              core.info(`Cache compressed and saved (${sizeFormatted})`);
            }
            resolve();
          }
        });
      });
      
      // Save content hash for future comparisons
      const hashFile = cacheFile + '.hash';
      if (currentHash) {
        fs.writeFileSync(hashFile, currentHash);
        core.info(`Hash saved to: ${hashFile}`);
      }
    }
    
    // Fix permissions
    const username = process.env.USER || 'runner';
    await new Promise((resolve) => {
      exec(`sudo chown ${username}:${username} "${cacheFile}"`, (error) => {
        if (error) {
          core.warning(`Failed to change permissions: ${error.message}`);
        }
        resolve();
      });
    });
    
    // Cache save success message is now handled during tar creation
  } catch (error) {
    core.setFailed(error.message);
  }
}

run();