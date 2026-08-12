const yaml = require('yaml');
const fs = require('fs');
const path = require('path');

const isAlasPath = (candidate: string) => (
  fs.existsSync(path.join(candidate, 'config', 'deploy.yaml'))
  && fs.existsSync(path.join(candidate, 'gui.py'))
);

/**
 * Find the Alas checkout independently of Electron's working directory.
 *
 * Finder starts packaged macOS apps with `/` as their current directory, while
 * development starts them from `webapp/`.  An explicit ALAS_PATH takes
 * precedence; otherwise walk upward from both locations to support the local
 * app bundle generated inside this checkout.
 */
const resolveAlasPath = () => {
  const candidates = process.env.ALAS_PATH ? [path.resolve(process.env.ALAS_PATH)] : [];
  const roots = [process.cwd(), path.dirname(process.execPath)];

  for (const root of roots) {
    let candidate = path.resolve(root);
    while (true) {
      candidates.push(candidate);
      const parent = path.dirname(candidate);
      if (parent === candidate) break;
      candidate = parent;
    }
  }

  const alasRoot = candidates.find(isAlasPath);
  if (!alasRoot) {
    throw new Error('Unable to find Alas. Set ALAS_PATH to the directory containing config/deploy.yaml.');
  }
  return alasRoot;
};

export const alasPath = resolveAlasPath();

const file = fs.readFileSync(path.join(alasPath, './config/deploy.yaml'), 'utf8');
const config = yaml.parse(file);
const PythonExecutable = config.Deploy.Python.PythonExecutable;
const WebuiPort = config.Deploy.Webui.WebuiPort.toString();

export const pythonPath = (path.isAbsolute(PythonExecutable) ? PythonExecutable : path.join(alasPath, PythonExecutable));
export const webuiUrl = `http://127.0.0.1:${WebuiPort}`;
export const webuiPath = 'gui.py';
export const webuiArgs = ['--port', WebuiPort, '--electron'];
export const dpiScaling = Boolean(config.Deploy.Webui.DpiScaling) || (config.Deploy.Webui.DpiScaling === undefined) ;
