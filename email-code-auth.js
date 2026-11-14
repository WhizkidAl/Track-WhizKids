/* Shared email-code sign-in. Participant access remains enforced by Supabase RLS. */
window.createEmailCodeAuth = function (db, setStatus) {
  const el = id => document.getElementById(id);
  let busy = false, nextSend = 0;
  function emailAddress() {
    const input = el('authEmail');
    input.value = input.value.trim();
    if (!input.value || !input.reportValidity()) {
      setStatus('Enter your authorised email address.');
      input.focus();
      return null;
    }
    return input.value;
  }
  function controls(disabled) {
    el('sendLinkBtn').disabled = disabled;
    el('verifyOtpBtn').disabled = disabled;
    el('authEmail').disabled = disabled;
  }
  async function run(operation, success) {
    if (busy) return;
    busy = true;
    controls(true);
    try {
      const { error } = await operation();
      if (error) throw error;
      success();
    } catch (error) {
      setStatus(error.status === 429
        ? 'Please wait before requesting another code, then try again.'
        : 'Sign-in was not completed. Check your connection and email address. If the code is invalid or expired, request a new code and use the newest email.');
    } finally {
      busy = false;
      controls(false);
      el('authEmail').disabled = el('sendLinkBtn').style.display === 'none';
    }
  }
  return {
    async send() {
      if (busy) return;
      const email = emailAddress();
      if (!email) return;
      if (Date.now() < nextSend) {
        setStatus('Please wait ' + Math.ceil((nextSend - Date.now()) / 1000) + ' seconds before requesting another code.');
        return;
      }
      setStatus('Sending secure sign-in code…');
      await run(() => db.auth.signInWithOtp({ email, options: {
        // Preserve first-time access: pending authorised emails attach after sign-in.
        shouldCreateUser: true,
        emailRedirectTo: window.location.origin + window.location.pathname
      } }), () => {
        nextSend = Date.now() + 60000;
        el('authOtp').value = '';
        el('sendLinkBtn').textContent = 'Send a new code';
        setStatus('Code requested. Check your inbox and junk folder. Enter the 6-digit code from the newest email here; you can read the email on another device.');
        el('authOtp').focus();
      });
    },
    async verify() {
      if (busy) return;
      const email = emailAddress();
      if (!email) return;
      const token = el('authOtp').value.trim();
      if (!/^\d{6}$/.test(token)) {
        setStatus('Enter all 6 digits from the newest sign-in email.');
        el('authOtp').focus();
        return;
      }
      setStatus('Checking code…');
      await run(() => db.auth.verifyOtp({ email, token, type: 'email' }), () => {
        el('authOtp').value = '';
        setStatus('Signed in. Loading your authorised participants…');
      });
    },
    render(signedIn) {
      el('otpField').style.display = signedIn ? 'none' : '';
      el('otpActions').style.display = signedIn ? 'none' : '';
      el('authOtp').value = '';
      if (!signedIn) setStatus('Enter your authorised email, request a code, then enter the 6-digit code here. This is a one-time code, not a permanent PIN.');
    }
  };
};
