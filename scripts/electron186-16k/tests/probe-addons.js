console.log('versions', JSON.stringify(process.versions));
for (const moduleName of ['ThunderHelper', 'ThunderKernel']) {
 try {
   const addon = require(process.env.THUNDER_RUNTIME + '/resources/bin/' + moduleName + '.node');
   console.log(moduleName, 'loaded', Object.keys(addon).sort().join(','));
 } catch (error) {
   console.error(moduleName, error && error.stack || String(error));
   process.exitCode=1;
 }
}
process.exit(process.exitCode || 0);
