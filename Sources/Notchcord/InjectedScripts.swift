import Foundation

enum InjectedScripts {
    /// Localized strings handed to the page script.
    static var l10nJSON: String {
        let d = ["attachment": L.t("📎 attachment", "📎 anexo"),
                 "link": "🔗 link",
                 "sticker": L.t("sticker", "figurinha")]
        let data = (try? JSONSerialization.data(withJSONObject: d)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Compact-mode CSS: only applies with <html data-notchcord="compact"> (/channels/ routes in island web views).
    /// Class-prefix selectors because Discord uses hashed class names (e.g. guilds_a4d4d9).
    static let css = #"""
    (() => {
      const css = `
      html[data-notchcord="compact"] nav[class*="guilds_"],
      html[data-notchcord="compact"] [class*="sidebar_"][class*="container_"],
      html[data-notchcord="compact"] div[class^="sidebar_"],
      html[data-notchcord="compact"] [class*="membersWrap_"],
      html[data-notchcord="compact"] [class*="notice_"] { display: none !important; }
      /* Discord's own title bar (server name, inbox, help) duplicates our tabs */
      html[data-notchcord="compact"] div[class^="bar_"]:has(> div[class^="title_"]) { display: none !important; }
      html[data-notchcord="compact"] div[class^="base_"]:has(> div[class^="bar_"] > div[class^="title_"]) {
        grid-template-rows: [top] 0px [titleBarEnd] min-content [noticeEnd] 1fr [end] !important;
      }
      html[data-notchcord="compact"] ::-webkit-scrollbar { width: 6px !important; height: 6px !important; }
      `;
      const add = () => {
        if (document.getElementById('notchcord-css')) return;
        const s = document.createElement('style'); s.id = 'notchcord-css'; s.textContent = css;
        (document.head || document.documentElement).appendChild(s);
      };
      add(); document.addEventListener('DOMContentLoaded', add);
      window.__ncSetCSS = (t) => { add(); document.getElementById('notchcord-css').textContent = t; };
    })();
    """#

    /// Route, title and new messages -> native app.
    static let boot = #"""
    (() => {
      if (window.__ncBoot) return; window.__ncBoot = true;
      const post = (type, data) => { try { webkit.messageHandlers.notchcord.postMessage(Object.assign({type}, data)); } catch (e) {} };
      const root = document.documentElement;
      let lastPath = null, lastTitle = null;
      const T = window.__ncL10n || {};

      // --- route / title ---
      const tick = () => {
        const p = location.pathname, t = document.title;
        root.dataset.notchcord = (window.__ncCompact && p.startsWith('/channels/')) ? 'compact' : 'full';
        if (p !== lastPath || t !== lastTitle) {
          if (p !== lastPath) arm();
          lastPath = p; lastTitle = t;
          post('route', { path: p, title: t });
        }
      };

      // --- new messages (snowflake ids grow over time) ---
      let maxId = 0n, armedUntil = 0;
      const sel = 'li[id^="chat-messages-"]';
      const snow = (li) => { try { return BigInt(li.id.split('-').pop()); } catch (e) { return 0n; } };
      const scanMax = () => { document.querySelectorAll(sel).forEach(li => { const s = snow(li); if (s > maxId) maxId = s; }); };
      function arm() { maxId = 0n; armedUntil = Date.now() + 3000; }

      // message id = last chunk of "chat-messages-<channel>-<message>"
      const mid = (li) => li.id.split('-').pop();
      const byId = (root, id) => root.querySelector('[id="' + id + '"]');

      // author: the message's own header; for grouped messages, the first message of the group.
      // (replies embed the quoted message inside the same <li>, so never take "the first match")
      const authorOf = (li) => {
        let n = li;
        for (let i = 0; n && i < 80; i++, n = n.previousElementSibling) {
          if (!n.id || !n.id.startsWith('chat-messages-')) continue;
          const u = byId(n, 'message-username-' + mid(n));
          if (u) {
            const name = (u.querySelector('[class*="username_"]') || u).textContent.trim();
            const img = n.querySelector('img[class^="avatar_"], img[class*=" avatar_"]');
            return { name, avatar: img ? img.src : null };
          }
        }
        return { name: '', avatar: null };
      };
      const textOf = (li) => {
        const c = byId(li, 'message-content-' + mid(li));
        let t = c ? c.innerText.trim() : '';
        if (!t) {
          const acc = li.querySelector('[id^="message-accessories-"]');
          if (acc && acc.querySelector('img, video, [class*="attachment"]')) t = T.attachment || '📎';
          else if (acc && acc.querySelector('[class*="embed"]')) t = T.link || '🔗';
          else if (li.querySelector('[class*="sticker"]')) t = T.sticker || 'sticker';
        }
        return t;
      };
      const replyTo = (li) => {
        const ctx = li.querySelector('[id^="message-reply-context-"], [class*="repliedMessage_"]');
        if (!ctx) return '';
        const u = ctx.querySelector('[class*="username_"]');
        return u ? u.textContent.trim().replace(/^@/, '') : '';
      };

      const obs = new MutationObserver(() => {
        if (Date.now() < armedUntil || maxId === 0n) { scanMax(); return; }
        const fresh = [];
        document.querySelectorAll(sel).forEach(li => { const s = snow(li); if (s > maxId) fresh.push([s, li]); });
        if (!fresh.length) return;
        fresh.sort((a, b) => (a[0] < b[0] ? -1 : 1));
        maxId = fresh[fresh.length - 1][0];
        // give React a moment to fill in author/content
        setTimeout(() => fresh.forEach(([, li]) => {
          const a = authorOf(li);
          post('message', { author: a.name, avatar: a.avatar, text: textOf(li), replyTo: replyTo(li) });
        }), 120);
      });

      window.__ncFocus = () => {
        const tb = document.querySelector('[role="textbox"][contenteditable="true"]');
        if (tb) { tb.focus(); return true; } return false;
      };

      const start = () => {
        if (!document.body) return setTimeout(start, 100);
        obs.observe(document.body, { childList: true, subtree: true });
        tick(); setInterval(tick, 400);
      };
      arm(); start();
    })();
    """#
}
