export enum CoreRecoveryDecision {
  IGNORE = 'IGNORE',
  RECOVER = 'RECOVER',
  STOP = 'STOP'
}

/** 每次 reset 后最多自动恢复一次；恢复期间的重复异常忽略，再次退出则停止。 */
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
