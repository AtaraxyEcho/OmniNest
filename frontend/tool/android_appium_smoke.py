"""Android Appium smoke v4 - works with existing session."""
from __future__ import annotations

import json
import time
from pathlib import Path

from appium import webdriver
from appium.options.android import UiAutomator2Options
from appium.webdriver.common.appiumby import AppiumBy
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

RESULTS: list[dict] = []
SHOTS = Path(r"C:\Users\Ataraxy\AppData\Local\Temp\android-appium")
SHOTS.mkdir(parents=True, exist_ok=True)


def record(case_id: str, ok: bool, note: str) -> None:
    RESULTS.append({"id": case_id, "ok": ok, "note": note})
    print(f"{'PASS' if ok else 'FAIL'} | {case_id} | {note}", flush=True)


def shot(driver, name: str) -> None:
    try:
        driver.save_screenshot(str(SHOTS / f"{name}.png"))
    except Exception as exc:  # noqa: BLE001
        print("shot fail", name, exc, flush=True)


def wait(driver, timeout=20):
    return WebDriverWait(driver, timeout)


def collect(driver):
    descs, texts = [], []
    for by, val in (
        (AppiumBy.CLASS_NAME, "android.view.View"),
        (AppiumBy.CLASS_NAME, "android.widget.TextView"),
        (AppiumBy.CLASS_NAME, "android.widget.Button"),
        (AppiumBy.CLASS_NAME, "android.widget.EditText"),
    ):
        try:
            els = driver.find_elements(by, val)
        except Exception:
            continue
        for el in els:
            try:
                d = el.get_attribute("content-desc") or ""
                if d and 0 < len(d) < 150 and d != "null":
                    descs.append(d.replace("\n", " ")[:120])
                t = el.text or ""
                if t and len(t) < 150:
                    texts.append(t.replace("\n", " ")[:120])
            except Exception:
                continue
    return descs, texts


def click_label(driver, label: str, timeout=6) -> bool:
    candidates = [
        (AppiumBy.ACCESSIBILITY_ID, label),
        (AppiumBy.XPATH, f'//*[starts-with(@content-desc, "{label}")]'),
        (AppiumBy.XPATH, f'//*[@content-desc="{label}&#10;{label}"]'),
        (AppiumBy.ANDROID_UIAUTOMATOR, f'new UiSelector().descriptionContains("{label}")'),
    ]
    end = time.time() + timeout
    while time.time() < end:
        for by, val in candidates:
            try:
                els = driver.find_elements(by, val)
            except Exception:
                continue
            for el in els:
                try:
                    if el.is_displayed():
                        el.click()
                        return True
                except Exception:
                    continue
        time.sleep(0.4)
    return False


def main() -> int:
    options = UiAutomator2Options()
    options.platform_name = "Android"
    options.automation_name = "UiAutomator2"
    options.device_name = "emulator-5554"
    options.udid = "emulator-5554"
    options.app_package = "com.omninest.app"
    options.app_activity = ".MainActivity"
    options.no_reset = True
    options.auto_grant_permissions = True
    options.new_command_timeout = 240

    driver = webdriver.Remote("http://127.0.0.1:4723", options=options)
    driver.implicitly_wait(2)
    try:
        try:
            driver.activate_app("com.omninest.app")
        except Exception:
            pass
        time.sleep(10)
        shot(driver, "v4-01")

        descs, texts = collect(driver)
        blob = "\n".join(descs + texts)
        on_login = "欢迎回来" in blob or any("EditText" in _ for _ in [])
        # detect login fields
        fields = driver.find_elements(AppiumBy.CLASS_NAME, "android.widget.EditText")
        if len(fields) >= 2:
            record("AN-SESSION", False, "仍停在登录页，尝试登录")
            user_field, pass_field = fields[0], fields[1]
            for f in fields:
                if (f.get_attribute("password") or "").lower() == "true":
                    pass_field = f
                else:
                    user_field = f
            user_field.click(); user_field.send_keys("admin")
            pass_field.click(); pass_field.send_keys("TestAdmin!2026")
            click_label(driver, "登录", 6)
            time.sleep(8)
            descs, texts = collect(driver)
            blob = "\n".join(descs + texts)

        portal = any(k in blob for k in ("早上好", "系统摘要", "继续使用", "首页", "文件"))
        record("S-09", portal, f"portal={portal} sample={blob[:180]}")

        # nav modules
        for label, case in [
            ("文件", "S-14"),
            ("照片", "S-21"),
            ("媒体", "S-23"),
            ("音乐", "S-25"),
            ("阅读", "S-27"),
            ("首页", "S-09b"),
        ]:
            time.sleep(1.2)
            ok = click_label(driver, label, 7)
            time.sleep(3.5)
            shot(driver, f"v4-{label}")
            d2, t2 = collect(driver)
            crashed = any("停止运行" in x or "无响应" in x for x in d2 + t2)
            # page-specific marker
            joined = "\n".join(d2 + t2)
            markers = {
                "文件": ("全部文件", "回收站", "上传"),
                "照片": ("时间线", "相册", "照片"),
                "媒体": ("影视", "影片", "继续观看", "媒体"),
                "音乐": ("歌单", "音乐", "播放"),
                "阅读": ("书库", "书架", "阅读"),
                "首页": ("早上好", "系统摘要", "继续使用"),
            }
            hit = any(m in joined for m in markers.get(label, (label,)))
            record(case, ok and not crashed and hit, f"click={ok} crash={crashed} marker={hit}")
            try:
                driver.back()
            except Exception:
                pass
            time.sleep(2)

        state = driver.query_app_state("com.omninest.app")
        record("AN-ALIVE", int(state) >= 3, f"state={state}")

    finally:
        try:
            driver.quit()
        except Exception:
            pass

    passed = sum(1 for r in RESULTS if r["ok"])
    failed = len(RESULTS) - passed
    (SHOTS / "summary.json").write_text(
        json.dumps({"passed": passed, "failed": failed, "total": len(RESULTS), "results": RESULTS},
                   ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps({"passed": passed, "failed": failed, "total": len(RESULTS)}, ensure_ascii=False))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
