# PlaneChat 구조 설명서

## 개요

비행기 내에서 인터넷 없이 모바일 핫스팟 등 로컬 네트워크만으로 동작하는 P2P 채팅 앱.
별도 서버 없이 앱 자체가 서버/클라이언트 역할을 동시에 수행한다.

## 동작 원리

1. 앱 실행 시 UDP 브로드캐스트(포트 41234)를 3초마다 전송하여 같은 네트워크의 다른 피어를 탐색
2. 새 피어 발견 시 TCP(포트 41235)로 연결하여 실시간 메시지 교환
3. 가장 먼저 접속한 피어가 호스트 역할 (피어 목록, 채팅방 목록 관리 및 배포)
4. 호스트가 나가면 그 다음 오래된 피어가 자동으로 호스트 승계

## 디렉토리 구조

```
lib/
├── main.dart                     # 앱 진입점
├── models/
│   ├── peer.dart                 # 피어(접속자) 데이터 모델
│   ├── message.dart              # 채팅 메시지 데이터 모델
│   └── chat_room.dart            # 채팅방 데이터 모델
├── services/
│   ├── network_service.dart      # 핵심 네트워크 로직
│   └── storage_service.dart      # 로컬 저장소 서비스
├── providers/
│   └── app_state.dart            # 중앙 상태 관리
└── screens/
    ├── name_screen.dart          # 이름 입력 화면
    ├── lobby_screen.dart         # 로비 화면
    └── chat_screen.dart          # 채팅방 화면
```

## 모델 (lib/models/)

### Peer (peer.dart)

접속자 한 명을 나타내는 데이터 클래스.

| 필드 | 타입 | 설명 |
|------|------|------|
| id | String | 고유 식별자 (UUID) |
| name | String | 사용자가 입력한 이름 |
| address | String | IP 주소 |
| port | int | TCP 포트 번호 |
| isOnline | bool | 현재 온라인 여부 |
| joinedAt | DateTime | 최초 접속 시각 (호스트 선출에 사용) |

### Message (message.dart)

채팅 메시지 한 건을 나타내는 데이터 클래스.

| 필드 | 타입 | 설명 |
|------|------|------|
| id | String | 메시지 고유 ID |
| senderName | String | 보낸 사람 이름 |
| senderId | String | 보낸 사람 ID |
| content | String | 메시지 내용 |
| timestamp | DateTime | 전송 시각 |
| roomId | String | 소속 채팅방 ID |

### ChatRoom (chat_room.dart)

채팅방 정보를 나타내는 데이터 클래스.

| 필드 | 타입 | 설명 |
|------|------|------|
| id | String | 채팅방 고유 ID |
| name | String | 채팅방 이름 |
| creatorId | String | 생성자 ID |
| creatorName | String | 생성자 이름 |
| createdAt | DateTime | 생성 시각 |
| participantIds | List\<String\> | 현재 참여자 ID 목록 |

## 서비스 (lib/services/)

### NetworkService (network_service.dart)

P2P 통신의 핵심 로직을 담당하는 클래스.

**주요 기능:**

| 메서드 | 역할 |
|--------|------|
| start() | UDP/TCP 소켓을 열고 네트워크 서비스 시작 |
| stop() | 모든 연결 종료 및 자원 해제 |
| createRoom() | 새 채팅방 생성 후 전체 피어에 알림 |
| joinRoom() | 채팅방 참여 요청 브로드캐스트 |
| leaveRoom() | 채팅방 퇴장 알림 |
| sendMessage() | 메시지 전송 (호스트가 중계) |

**내부 동작:**

| 메서드 | 역할 |
|--------|------|
| _startUdpBroadcast() | UDP 소켓 바인딩, 3초 주기 브로드캐스트 시작 |
| _sendBroadcast() | 자신의 정보를 UDP 브로드캐스트로 전송 |
| _handleUdpMessage() | 수신된 UDP 패킷 파싱, 새 피어 등록 |
| _startTcpServer() | TCP 서버 소켓 오픈, 연결 수락 |
| _connectToPeer() | 발견된 피어에 TCP 클라이언트로 연결 |
| _handleTcpMessage() | TCP로 수신된 JSON 메시지 타입별 처리 |
| _handleDisconnect() | 피어 연결 해제 처리, 호스트 재선출 |
| _electHost() | joinedAt이 가장 빠른 온라인 피어를 호스트로 선출 |
| _broadcastPeerList() | 호스트가 전체 피어 목록을 모든 피어에 전송 |
| _broadcastRoomList() | 호스트가 채팅방 목록을 모든 피어에 전송 |
| _broadcastToRoom() | 특정 채팅방 참여자에게만 메시지 전달 |

**콜백:**

| 콜백 | 발동 시점 |
|------|----------|
| onPeersChanged | 피어 목록 변경 시 |
| onRoomsChanged | 채팅방 목록 변경 시 |
| onMessageReceived | 새 메시지 수신 시 |
| onHostChanged | 호스트 변경 시 |

### StorageService (storage_service.dart)

SharedPreferences를 이용한 로컬 데이터 영속화.

| 메서드 | 역할 |
|--------|------|
| init() | SharedPreferences 인스턴스 초기화 |
| getSavedName() / saveName() | 사용자 이름 읽기/저장 |
| getSavedUserId() / saveUserId() | 사용자 ID 읽기/저장 |
| getMessages() | 특정 채팅방의 저장된 메시지 불러오기 |
| saveMessages() | 채팅방 메시지 전체 덮어쓰기 저장 |
| appendMessage() | 채팅방에 메시지 1건 추가 저장 |

## 상태 관리 (lib/providers/)

### AppState (app_state.dart)

ChangeNotifier를 상속하여 전체 앱 상태를 관리하는 중앙 클래스.

**상태 필드:**

| 필드 | 타입 | 설명 |
|------|------|------|
| _userId | String? | 현재 사용자 고유 ID |
| _currentUserName | String? | 현재 사용자 이름 |
| _peers | List\<Peer\> | 발견된 전체 피어 목록 |
| _rooms | List\<ChatRoom\> | 현재 열려있는 채팅방 목록 |
| _messages | Map\<String, List\<Message\>\> | 채팅방별 메시지 목록 |
| _hostId | String? | 현재 호스트 피어 ID |

**주요 메서드:**

| 메서드 | 역할 |
|--------|------|
| _init() | 저장소 초기화, 저장된 이름 복원, 네트워크 콜백 등록 |
| setName() | 이름 설정 후 네트워크 시작 |
| createRoom() | 채팅방 생성 |
| joinRoom() | 채팅방 참여 및 저장된 메시지 복원 |
| leaveRoom() | 채팅방 퇴장 |
| sendMessage() | 메시지 전송, 로컬 저장, UI 갱신 |

## 화면 (lib/screens/)

### NameScreen (name_screen.dart)

최초 실행 또는 이름이 저장되지 않은 상태일 때 표시.
이름 입력 후 AppState.setName() 호출.

### LobbyScreen (lobby_screen.dart)

좌측 패널: 온라인/오프라인 피어 목록, 호스트 표시
우측 패널: 열려있는 채팅방 목록
하단 FAB: 새 채팅방 만들기 다이얼로그

### ChatScreen (chat_screen.dart)

메시지 리스트 (말풍선 UI), 입력 필드.
입장 시 joinRoom(), 퇴장 시 leaveRoom() 자동 호출.

## 프로토콜 메시지 형식

TCP를 통해 주고받는 JSON 메시지들 (줄바꿈으로 구분):

| type | 방향 | 설명 |
|------|------|------|
| discovery | UDP 브로드캐스트 | 피어 존재 알림 |
| join | 클라이언트→호스트 | TCP 연결 후 참여 알림 |
| peer_list | 호스트→전체 | 전체 피어 목록 동기화 |
| room_list | 호스트→전체 | 채팅방 목록 동기화 |
| create_room | 생성자→전체 | 새 채팅방 생성 알림 |
| join_room | 참여자→전체 | 채팅방 참여 알림 |
| leave_room | 퇴장자→전체 | 채팅방 퇴장 알림 |
| chat_message | 발신자→호스트→채팅방 | 채팅 메시지 (호스트가 중계) |
| host_election | 새호스트→전체 | 호스트 변경 알림 |

## 실행 방법

```bash
cd PlaneChat
flutter pub get
flutter run -d macos
```

## 필요 권한 (macOS)

`macos/Runner/DebugProfile.entitlements`와 `macos/Runner/Release.entitlements`에 다음 권한 필요:
- `com.apple.security.network.client` - TCP/UDP 클라이언트 연결
- `com.apple.security.network.server` - TCP 서버 소켓 열기
