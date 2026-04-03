# Phase 0: project-setup

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `/docs/prd.md` — 제품 요구사항 (타겟, 기능, 디자인)
- `/docs/code-architecture.md` — 코드 아키텍처 (프로젝트 구조, 서비스 계약)
- `/docs/adr.md` — 기술 결정 기록 (iOS 17+, SwiftData, @Observable 등)

## 작업 내용

Xcode 프로젝트를 `xcodegen`으로 생성한다. 최종 결과물은 빈 앱이 시뮬레이터에서 빌드되는 것.

### 1. `project.yml` 생성 (프로젝트 루트)

```yaml
name: tic
options:
  bundleIdPrefix: com.tic
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "16.0"
  groupSortPosition: top
  createIntermediateGroups: true

settings:
  base:
    CODE_SIGN_IDENTITY: ""
    CODE_SIGNING_REQUIRED: "NO"
    CODE_SIGNING_ALLOWED: "NO"
    SWIFT_VERSION: "5.9"

targets:
  tic:
    type: application
    platform: iOS
    sources:
      - path: tic
    settings:
      base:
        INFOPLIST_FILE: tic/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.tic.app
        SUPPORTS_MAC_DESIGNED_FOR_IPHONE: false
        NSSupportsLiveActivities: true
    entitlements:
      path: tic/tic.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.tic.app

  ticWidgets:
    type: app-extension
    platform: iOS
    sources:
      - path: ticWidgets
    settings:
      base:
        INFOPLIST_FILE: ticWidgets/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.tic.app.widgets
        NSSupportsLiveActivities: true
    entitlements:
      path: ticWidgets/ticWidgets.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.tic.app
    dependencies:
      - target: tic
        embed: false
```

- 위 YAML은 참고용 뼈대다. xcodegen 문법에 맞게 조정하라.
- Widget Extension은 `app-extension` 타입이며, `WidgetKit`과 `ActivityKit` 프레임워크를 사용한다.
- Widget Extension의 `PRODUCT_BUNDLE_IDENTIFIER`는 반드시 메인 앱의 하위여야 한다 (`com.tic.app.widgets`).
- entitlements에 App Group (`group.com.tic.app`)을 양쪽 타겟에 추가한다.

### 2. 디렉토리 및 파일 생성

다음 디렉토리와 최소 파일을 생성하라:

```
tic/
├── ticApp.swift          // @main App, 빈 WindowGroup
├── ContentView.swift     // "tic" 텍스트만 표시하는 뷰
├── Info.plist            // NSCalendarsUsageDescription, NSRemindersUsageDescription
├── tic.entitlements
├── Assets.xcassets/
│   └── AccentColor.colorset/
│       └── Contents.json  // 오렌지 색상 (#FF6F00 또는 적절한 오렌지)
│   └── AppIcon.appiconset/
│       └── Contents.json  // 빈 아이콘셋
├── Models/               // 빈 디렉토리 (다음 phase에서 사용)
├── Services/             // 빈 디렉토리
├── ViewModels/           // 빈 디렉토리
├── Views/
│   └── Calendar/         // 빈 디렉토리
│   └── Components/       // 빈 디렉토리
├── Extensions/           // 빈 디렉토리

ticWidgets/
├── TicWidgetBundle.swift  // @main WidgetBundle, 빈 body
├── Info.plist
├── ticWidgets.entitlements
```

### 3. Info.plist 설정

**메인 앱 Info.plist:**
```xml
NSCalendarsUsageDescription: "tic에서 캘린더 일정을 확인하고 관리하기 위해 접근 권한이 필요합니다."
NSRemindersUsageDescription: "tic에서 미리 알림을 확인하고 관리하기 위해 접근 권한이 필요합니다."
NSSupportsLiveActivities: true
```

**Widget Info.plist:**
```xml
NSExtension:
  NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

### 4. ticApp.swift

```swift
import SwiftUI

@main
struct ticApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 5. ContentView.swift

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("tic")
    }
}
```

### 6. TicWidgetBundle.swift

```swift
import WidgetKit
import SwiftUI

@main
struct TicWidgetBundle: WidgetBundle {
    var body: some Widget {
        // 위젯은 Phase 7에서 추가
    }
}
```

### 7. AccentColor 설정

AccentColor.colorset의 Contents.json에 오렌지 색상을 설정하라:
- Light mode: `#FF6F00` (또는 비슷한 오렌지)
- Dark mode: 동일하거나 약간 밝은 오렌지

### 8. xcodegen 실행

```bash
cd /Users/leesm/work/side/tic && xcodegen generate
```

프로젝트 생성 후 빌드 테스트:
```bash
xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

빌드가 성공하면 AC 통과.

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/0-tic-mvp/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.
작업 중 사용자 개입이 반드시 필요한 상황이 발생하면 status를 `"blocked"`로, `"blocked_reason"` 필드에 사유를 기록하고 작업을 즉시 중단하라.

## 주의사항

- `xcodegen`은 `/opt/homebrew/bin/xcodegen`에 설치되어 있다. 별도 설치 불필요.
- `@main`이 메인 앱과 Widget Extension 양쪽에 있으므로, 각 타겟의 소스 경로가 겹치지 않도록 주의하라.
- `.gitignore`에 `*.xcodeproj`, `*.xcworkspace`, `DerivedData/` 등 Xcode 생성물을 추가하라. 단, `project.yml`은 커밋해야 한다.
- 빈 디렉토리는 `.gitkeep` 파일을 넣어 git에 추적되도록 하라.
- Widget Extension에 `@main`이 있으므로 메인 앱 타겟에 ticWidgets 소스가 포함되면 안 된다.
- `xcodebuild` 시 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. 사용 가능한 시뮬레이터를 `xcrun simctl list devices available` 로 확인하고 적절히 조정하라.
