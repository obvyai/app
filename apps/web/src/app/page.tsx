'use client';

import { useAuthenticator } from '@aws-amplify/ui-react';
import { Header } from '@/components/layout/header';
import { ImageGenerationForm } from '@/components/generation/image-generation-form';
import { RecentGenerations } from '@/components/generation/recent-generations';
import { WelcomeSection } from '@/components/ui/welcome-section';
import { LoadingSpinner } from '@/components/ui/loading-spinner';

export default function HomePage() {
  const { authStatus, user } = useAuthenticator((context) => [
    context.authStatus,
    context.user,
  ]);

  if (authStatus === 'configuring') {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <Header />
      
      <main className="container mx-auto px-4 py-8">
        {authStatus === 'authenticated' && user ? (
          <div className="space-y-8">
            {/* Welcome Section */}
            <WelcomeSection user={user} />
            
            {/* Main Content Grid */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
              {/* Image Generation Form */}
              <div className="lg:col-span-2">
                <div className="bg-card border border-border rounded-lg p-6">
                  <h2 className="text-2xl font-semibold mb-6">Generate Image</h2>
                  <ImageGenerationForm />
                </div>
              </div>
              
              {/* Recent Generations Sidebar */}
              <div className="lg:col-span-1">
                <div className="bg-card border border-border rounded-lg p-6">
                  <h2 className="text-xl font-semibold mb-4">Recent Generations</h2>
                  <RecentGenerations />
                </div>
              </div>
            </div>
          </div>
        ) : (
          <div className="max-w-4xl mx-auto text-center py-16">
            <div className="space-y-6">
              <h1 className="text-4xl font-bold gradient-bg bg-clip-text text-transparent">
                Welcome to Obvy Image Generator
              </h1>
              <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
                Create stunning AI-generated images using advanced Stable Diffusion models. 
                Sign in to start generating your creative visions.
              </p>
              
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mt-12">
                <div className="p-6 bg-card border border-border rounded-lg">
                  <div className="w-12 h-12 bg-primary/10 rounded-lg flex items-center justify-center mb-4 mx-auto">
                    <svg className="w-6 h-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                    </svg>
                  </div>
                  <h3 className="font-semibold mb-2">Lightning Fast</h3>
                  <p className="text-sm text-muted-foreground">
                    Generate high-quality images in seconds with our optimized GPU infrastructure.
                  </p>
                </div>
                
                <div className="p-6 bg-card border border-border rounded-lg">
                  <div className="w-12 h-12 bg-primary/10 rounded-lg flex items-center justify-center mb-4 mx-auto">
                    <svg className="w-6 h-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
                    </svg>
                  </div>
                  <h3 className="font-semibold mb-2">High Quality</h3>
                  <p className="text-sm text-muted-foreground">
                    Powered by Stable Diffusion XL for exceptional detail and artistic quality.
                  </p>
                </div>
                
                <div className="p-6 bg-card border border-border rounded-lg">
                  <div className="w-12 h-12 bg-primary/10 rounded-lg flex items-center justify-center mb-4 mx-auto">
                    <svg className="w-6 h-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1" />
                    </svg>
                  </div>
                  <h3 className="font-semibold mb-2">Cost Effective</h3>
                  <p className="text-sm text-muted-foreground">
                    Pay only for what you use with our scale-to-zero architecture.
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}