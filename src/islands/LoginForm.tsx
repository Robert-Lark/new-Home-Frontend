/** @jsxImportSource preact */
import { useState } from 'preact/hooks';
import { createSupabaseBrowserClient } from '../lib/supabase';

type Status = 'idle' | 'sending' | 'sent' | 'error';

export default function LoginForm() {
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<Status>('idle');
  const [msg, setMsg] = useState('');

  const submit = async (e: Event) => {
    e.preventDefault();
    if (!email || status === 'sending') return;
    setStatus('sending');
    setMsg('');
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: true,
        emailRedirectTo: `${window.location.origin}/auth/confirm`,
      },
    });
    if (error) {
      setStatus('error');
      setMsg(error.message);
    } else {
      setStatus('sent');
    }
  };

  if (status === 'sent') {
    return (
      <div class="login-sent">
        <p class="login-sent-t">Check your inbox.</p>
        <p class="login-sent-s">
          We sent a one-time sign-in link to <strong>{email}</strong>. It expires shortly — open it
          on this device.
        </p>
        <button
          class="login-textlink"
          onClick={() => {
            setStatus('idle');
            setEmail('');
          }}
        >
          Use a different email
        </button>
      </div>
    );
  }

  return (
    <form class="login-form" onSubmit={submit}>
      <label class="login-label" for="qc-email">Email</label>
      <input
        id="qc-email"
        class="login-input"
        type="email"
        required
        autocomplete="email"
        placeholder="you@example.com"
        value={email}
        onInput={(e) => setEmail((e.currentTarget as HTMLInputElement).value)}
        disabled={status === 'sending'}
      />
      <button class="login-submit" type="submit" disabled={status === 'sending'}>
        {status === 'sending' ? 'Sending…' : 'Send me a link'}
      </button>
      {status === 'error' && <p class="login-error">{msg || 'Something went wrong. Try again.'}</p>}
    </form>
  );
}
