enum LwwDecision { keepLocal, takeRemote }

LwwDecision compareLww({
  required int localLamport,
  required String localDeviceId,
  required int remoteLamport,
  required String remoteDeviceId,
}) {
  if (remoteLamport > localLamport) {
    return LwwDecision.takeRemote;
  }
  if (remoteLamport < localLamport) {
    return LwwDecision.keepLocal;
  }
  return remoteDeviceId.compareTo(localDeviceId) >= 0
      ? LwwDecision.takeRemote
      : LwwDecision.keepLocal;
}
