import {spawn, ChildProcess} from 'child_process';
import {powerSaveBlocker} from 'electron';

/**
 * Keeps the host awake only for the lifetime of the Alas Python process.
 *
 * Electron prevents app suspension without holding the display awake. On
 * macOS, `caffeinate -s` prevents automatic system sleep while connected to
 * AC power. Closing a MacBook lid is a forced sleep event, which macOS does
 * not allow normal application assertions to override. macOS releases the
 * assertion when the watched process exits.
 */
export class SleepInhibitor {
  private blockerId: number | null = null;
  private caffeinate: ChildProcess | null = null;

  start(processId: number | undefined): void {
    if (this.blockerId === null) {
      this.blockerId = powerSaveBlocker.start('prevent-app-suspension');
    }

    if (process.platform !== 'darwin' || !processId || this.caffeinate) {
      return;
    }

    // `-s` keeps the system awake on AC power without preventing display sleep.
    this.caffeinate = spawn('/usr/bin/caffeinate', ['-s', '-w', String(processId)], {
      stdio: 'ignore',
    });
    this.caffeinate.once('exit', () => {
      this.caffeinate = null;
    });
    this.caffeinate.once('error', () => {
      this.caffeinate = null;
    });
  }

  stop(): void {
    if (this.blockerId !== null) {
      if (powerSaveBlocker.isStarted(this.blockerId)) {
        powerSaveBlocker.stop(this.blockerId);
      }
      this.blockerId = null;
    }

    this.caffeinate?.kill();
    this.caffeinate = null;
  }
}
