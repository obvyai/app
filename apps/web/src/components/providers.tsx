'use client';

import { Amplify } from 'aws-amplify';
import { Authenticator } from '@aws-amplify/ui-react';
import '@aws-amplify/ui-react/styles.css';
import { SWRConfig } from 'swr';
import { ThemeProvider } from 'next-themes';
import { useEffect } from 'react';

// Configure Amplify
const amplifyConfig = {
  Auth: {
    Cognito: {
      userPoolId: process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID!,
      userPoolClientId: process.env.NEXT_PUBLIC_COGNITO_USER_POOL_CLIENT_ID!,
      identityPoolId: process.env.NEXT_PUBLIC_COGNITO_IDENTITY_POOL_ID!,
      loginWith: {
        oauth: {
          domain: process.env.NEXT_PUBLIC_COGNITO_DOMAIN!,
          scopes: ['email', 'openid', 'profile'],
          redirectSignIn: [
            typeof window !== 'undefined' ? window.location.origin + '/auth/callback' : 'http://localhost:3000/auth/callback'
          ],
          redirectSignOut: [
            typeof window !== 'undefined' ? window.location.origin + '/auth/logout' : 'http://localhost:3000/auth/logout'
          ],
          responseType: 'code',
        },
        email: true,
        username: false,
      },
    },
  },
};

// SWR configuration
const swrConfig = {
  fetcher: async (url: string) => {
    const response = await fetch(url, {
      headers: {
        'Content-Type': 'application/json',
        // Add auth headers here when needed
      },
    });
    
    if (!response.ok) {
      const error = new Error('An error occurred while fetching the data.');
      // Attach extra info to the error object
      (error as any).info = await response.json();
      (error as any).status = response.status;
      throw error;
    }
    
    return response.json();
  },
  revalidateOnFocus: false,
  revalidateOnReconnect: true,
  refreshInterval: 0,
  errorRetryCount: 3,
  errorRetryInterval: 1000,
};

// Amplify theme customization
const amplifyTheme = {
  name: 'obvy-theme',
  tokens: {
    colors: {
      brand: {
        primary: {
          10: 'hsl(var(--primary))',
          80: 'hsl(var(--primary))',
          90: 'hsl(var(--primary))',
          100: 'hsl(var(--primary))',
        },
      },
      background: {
        primary: 'hsl(var(--background))',
        secondary: 'hsl(var(--card))',
      },
      font: {
        primary: 'hsl(var(--foreground))',
        secondary: 'hsl(var(--muted-foreground))',
      },
      border: {
        primary: 'hsl(var(--border))',
        secondary: 'hsl(var(--border))',
      },
    },
    components: {
      authenticator: {
        router: {
          boxShadow: '0 0 16px rgba(0, 0, 0, 0.1)',
          borderWidth: '1px',
          borderStyle: 'solid',
          borderColor: 'hsl(var(--border))',
        },
      },
      button: {
        primary: {
          backgroundColor: 'hsl(var(--primary))',
          color: 'hsl(var(--primary-foreground))',
          _hover: {
            backgroundColor: 'hsl(var(--primary))',
            opacity: '0.9',
          },
        },
      },
      fieldcontrol: {
        borderColor: 'hsl(var(--border))',
        _focus: {
          borderColor: 'hsl(var(--ring))',
          boxShadow: '0 0 0 2px hsl(var(--ring))',
        },
      },
    },
  },
};

export function Providers({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    // Configure Amplify on client side only
    if (typeof window !== 'undefined') {
      Amplify.configure(amplifyConfig);
    }
  }, []);

  return (
    <ThemeProvider
      attribute="class"
      defaultTheme="system"
      enableSystem
      disableTransitionOnChange
    >
      <SWRConfig value={swrConfig}>
        <Authenticator.Provider>
          <Authenticator
            theme={amplifyTheme}
            hideSignUp={false}
            loginMechanisms={['email']}
            signUpAttributes={['email', 'name']}
            socialProviders={[]}
            variation="modal"
          >
            {children}
          </Authenticator>
        </Authenticator.Provider>
      </SWRConfig>
    </ThemeProvider>
  );
}