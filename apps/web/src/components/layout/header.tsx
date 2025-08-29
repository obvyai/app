'use client';

import { useAuthenticator } from '@aws-amplify/ui-react';
import { Button } from '@/components/ui/button';
import { ThemeToggle } from '@/components/ui/theme-toggle';
import { UserMenu } from '@/components/ui/user-menu';
import Link from 'next/link';

export function Header() {
  const { authStatus, user, signOut } = useAuthenticator((context) => [
    context.authStatus,
    context.user,
    context.signOut,
  ]);

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="container mx-auto px-4">
        <div className="flex h-16 items-center justify-between">
          {/* Logo and Navigation */}
          <div className="flex items-center space-x-6">
            <Link href="/" className="flex items-center space-x-2">
              <div className="w-8 h-8 bg-primary rounded-lg flex items-center justify-center">
                <svg className="w-5 h-5 text-primary-foreground" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
              </div>
              <span className="text-xl font-bold">Obvy</span>
            </Link>
            
            {authStatus === 'authenticated' && (
              <nav className="hidden md:flex items-center space-x-6">
                <Link 
                  href="/" 
                  className="text-sm font-medium text-foreground hover:text-primary transition-colors"
                >
                  Generate
                </Link>
                <Link 
                  href="/gallery" 
                  className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors"
                >
                  Gallery
                </Link>
                <Link 
                  href="/models" 
                  className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors"
                >
                  Models
                </Link>
              </nav>
            )}
          </div>

          {/* Right side actions */}
          <div className="flex items-center space-x-4">
            <ThemeToggle />
            
            {authStatus === 'authenticated' && user ? (
              <UserMenu user={user} onSignOut={signOut} />
            ) : (
              <div className="flex items-center space-x-2">
                <Button variant="ghost" size="sm">
                  Sign In
                </Button>
                <Button size="sm">
                  Get Started
                </Button>
              </div>
            )}
          </div>
        </div>
      </div>
    </header>
  );
}