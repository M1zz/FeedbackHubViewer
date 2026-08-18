# todo

## 완료
- [x] 마지막 조회 결과를 기기에 저장(`FeedbackCache`, 환경별 JSON) → 실행 즉시 화면 표시
- [x] 실행 시 업데이트 확인은 스토어가 소유한 별도 태스크로 분리(화면이 기다리지 않음)
- [x] 레코드 타입별 증분 조회(마지막 조회 시각 이후 변경분) + 레코드명 기준 병합
- [x] 기기에 없는 데이터만 조회: 최신순으로 읽다가 이미 저장된 레코드를 만나면 페이지 중단
      (추가만 되는 Feedback·UsageEvent·CrashReport. UsageSnapshot은 덮어쓰기라 제외)
- [x] 스냅샷은 매번 전체를 읽으므로 내용 지문 비교로 불필요한 캐시 재작성 방지
- [x] 시스템 타임스탬프가 Queryable이 아니면 전체 조회로 자동 폴백, 그 결과를 캐시에 기억
- [x] 24시간 지난 캐시·수동 새로고침은 전체 재조회(콘솔에서 삭제된 레코드 반영)
- [x] "캐시 비우고 전체 다시 불러오기" 메뉴

## 남은 것
- [ ] (선택) CloudKit Console에서 `createdTimestamp`(Feedback·UsageEvent·CrashReport) /
      `modifiedTimestamp`(UsageSnapshot)를 QUERYABLE 인덱스로 추가 → 서버 쪽 날짜 필터까지 사용
      (없어도 새 레코드만 받습니다. README §5-7 참고, 코드 변경 없이 앱이 자동 감지)
- [ ] 앱이 꺼져 있을 때 알림: Push Notifications capability + `CKQuerySubscription`(미구현)
