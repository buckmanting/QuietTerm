# KAN-25 Phase 1 Validation Plan

`KAN-25` is scoped to Phase 1 only. Phase 2 command-matrix validation (`top/htop`, `vim/nano`, clear/reset, long-output fixture pass) is tracked separately.

## Scope

Phase 1 behaviors:

- A: connect to prompt and accept input
- B: auth failure shows retry flow without app restart
- C: disconnect and retry recover a usable session
- D: tab isolation prevents cross-routing of input/output
- E: tab close/select behavior remains stable
- F: foreground resume preserves valid sessions and reconciles dropped transports

## Closure Gates

- Every behavior A-F must have one passing unit test, one passing integration test (mocked/session-driven), and one passing UI test.
- Manual smoke must pass on the required matrix.
- Any reproducible defect blocks ticket closure.

## Automated Coverage Matrix

| Behavior | Unit | Integration | UI |
| --- | --- | --- | --- |
| A | `testAOpenSessionStartsInAuthenticatingState` | `testPasswordPromptTrustsHostKeyConnectsAndSendsInput` | `testMockSSHPasswordFlowConnectsTerminal` |
| B | `testBRetryFromFailedStateReturnsSessionToAuthenticating` | `testCancellingPasswordPromptKeepsFailedSessionForRetry` | `testMockSSHCancelPasswordKeepsTabWithRetryActions` |
| C | `testCRetryFromDisconnectedStateKeepsSameTabIdentity` | `testRetryReconnectsUsingSameSessionTab` | `testMockSSHDisconnectRetryReusesSameTab` |
| D | `testDClosingOneTabDoesNotChangeOtherTabState` | `testInputAndOutputRemainIsolatedAcrossConcurrentTabs` | `testMockSSHTabIsolationAndCloseKeepsActiveTabConnected` |
| E | `testEClosingSelectedTabFallsBackToLastTab` | `testClosingUnselectedTabPreservesSelectedTab` | `testMockSSHTabIsolationAndCloseKeepsActiveTabConnected` |
| F | `testFResumeMarksConnectedSessionDisconnectedWhenNoTransportExists` | `testResumeKeepsConnectedSessionWhenTransportStillActive` and `testResumeMarksConnectedSessionDisconnectedWhenTransportMissing` | `testMockSSHBackgroundResumeKeepsConnectedState` |

## Required Manual Matrix

- iPhone simulator: iOS 18, iOS 26.3
- iPad simulator: iPadOS 18, iPadOS 26.3
- Real iPhone: iOS 26.4

For each lane, run a Phase 1 smoke:

1. connect and enter input
2. force auth failure and verify retry
3. force disconnect and verify retry recovery
4. verify tab isolation and tab close/select behavior
5. background then foreground and verify expected session state

## Defect Policy

Create a Bug ticket for every reproducible failure with:

- device + OS
- app build/version
- fixture/server details
- reproduction steps
- expected vs actual behavior
- sanitized diagnostics/logs
