import {alasPath, pythonPath} from '/@/config';
import {SleepInhibitor} from '/@/sleep_inhibitor';

const {PythonShell} = require('python-shell');
const treeKill = require('tree-kill');
const {app} = require('electron');


export class PyShell extends PythonShell {
  private sleepInhibitor = new SleepInhibitor();
  private isStopping = false;

  constructor(script: string, args: Array<string> = []) {
    const options = {
      mode: 'text',
      args: args,
      pythonPath: pythonPath,
      scriptPath: alasPath,
    };
    super(script, options);

    const startSleepInhibitor = () => {
      if (this.childProcess.exitCode === null) {
        this.sleepInhibitor.start(this.childProcess.pid);
      }
    };
    if (app.isReady()) {
      startSleepInhibitor();
    } else {
      app.once('ready', startSleepInhibitor);
    }
    this.childProcess.once('exit', () => this.sleepInhibitor.stop());
  }

  on(event: string, listener: (...args: any[]) => void): this {
    this.removeAllListeners(event);
    super.on(event, listener);
    return this;
  }

  kill(callback: (...args: any[]) => void): this {
    this.sleepInhibitor.stop();
    const pid = this.childProcess.pid;
    if (this.isStopping || !pid || this.childProcess.exitCode !== null || this.childProcess.signalCode !== null) {
      callback();
      return this;
    }

    this.isStopping = true;
    treeKill(pid, 'SIGTERM', callback);
    return this;
  }
}
