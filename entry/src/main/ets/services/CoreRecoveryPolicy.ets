export enum CoreRecoveryDecision {
  IGNORE = 'IGNORE',
  RECOVER = 'RECOVER',
  STOP = 'STOP'
}

export class CoreRecoveryPolicy {
  private attempts: number = 0;
  private recoveryInProgress: boolean = false;

  reset(): void {
    this.attempts = 0;
    this.recoveryInProgress = false;
  }

  onUnexpectedExit(): CoreRecoveryDecision {
    if (this.recoveryInProgress) {
      return CoreRecoveryDecision.IGNORE;
    }
    if (this.attempts >= 1) {
      return CoreRecoveryDecision.STOP;
    }
    this.attempts++;
    this.recoveryInProgress = true;
    return CoreRecoveryDecision.RECOVER;
  }

  finishRecovery(): void {
    this.recoveryInProgress = false;
  }
}
