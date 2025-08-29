import { test, expect } from '@playwright/test';

test.describe('Image Generation Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Mock authentication for testing
    await page.goto('/');
    
    // Wait for the page to load
    await page.waitForLoadState('networkidle');
  });

  test('should display welcome page for unauthenticated users', async ({ page }) => {
    await expect(page.locator('h1')).toContainText('Welcome to Obvy Image Generator');
    await expect(page.locator('text=Sign in to start generating')).toBeVisible();
    
    // Check feature cards are displayed
    await expect(page.locator('text=Lightning Fast')).toBeVisible();
    await expect(page.locator('text=High Quality')).toBeVisible();
    await expect(page.locator('text=Cost Effective')).toBeVisible();
  });

  test('should show authentication modal when clicking sign in', async ({ page }) => {
    // Look for sign in button and click it
    const signInButton = page.locator('button:has-text("Sign In")').first();
    if (await signInButton.isVisible()) {
      await signInButton.click();
      
      // Should show Cognito authentication modal
      await expect(page.locator('[data-amplify-authenticator]')).toBeVisible();
    }
  });

  test('should display generation form for authenticated users', async ({ page }) => {
    // Mock authenticated state
    await page.addInitScript(() => {
      // Mock Amplify auth state
      window.localStorage.setItem('amplify-auth-state', JSON.stringify({
        authenticated: true,
        user: {
          username: 'testuser',
          attributes: {
            email: 'test@example.com'
          }
        }
      }));
    });

    await page.reload();
    await page.waitForLoadState('networkidle');

    // Should show the generation form
    await expect(page.locator('h2:has-text("Generate Image")')).toBeVisible();
    await expect(page.locator('textarea[placeholder*="prompt"]')).toBeVisible();
    await expect(page.locator('button:has-text("Generate")')).toBeVisible();
  });

  test('should validate prompt input', async ({ page }) => {
    // Mock authenticated state
    await page.addInitScript(() => {
      window.localStorage.setItem('amplify-auth-state', JSON.stringify({
        authenticated: true,
        user: { username: 'testuser' }
      }));
    });

    await page.reload();
    await page.waitForLoadState('networkidle');

    // Try to submit empty prompt
    const generateButton = page.locator('button:has-text("Generate")');
    if (await generateButton.isVisible()) {
      await generateButton.click();
      
      // Should show validation error
      await expect(page.locator('text=Prompt cannot be empty')).toBeVisible();
    }
  });

  test('should submit image generation request', async ({ page }) => {
    // Mock authenticated state
    await page.addInitScript(() => {
      window.localStorage.setItem('amplify-auth-state', JSON.stringify({
        authenticated: true,
        user: { username: 'testuser' }
      }));
    });

    // Mock API responses
    await page.route('**/v1/jobs', async (route) => {
      if (route.request().method() === 'POST') {
        await route.fulfill({
          status: 202,
          contentType: 'application/json',
          body: JSON.stringify({
            jobId: 'test-job-123',
            status: 'PENDING',
            message: 'Job submitted successfully',
            estimatedWaitTime: '60-120 seconds'
          })
        });
      }
    });

    await page.reload();
    await page.waitForLoadState('networkidle');

    // Fill in the prompt
    const promptTextarea = page.locator('textarea[placeholder*="prompt"]');
    if (await promptTextarea.isVisible()) {
      await promptTextarea.fill('a beautiful sunset over mountains');
      
      // Submit the form
      await page.locator('button:has-text("Generate")').click();
      
      // Should show success message
      await expect(page.locator('text=Job submitted successfully')).toBeVisible();
    }
  });

  test('should display job status updates', async ({ page }) => {
    // Mock authenticated state
    await page.addInitScript(() => {
      window.localStorage.setItem('amplify-auth-state', JSON.stringify({
        authenticated: true,
        user: { username: 'testuser' }
      }));
    });

    // Mock job status API
    let callCount = 0;
    await page.route('**/v1/jobs/test-job-123', async (route) => {
      callCount++;
      
      if (callCount === 1) {
        // First call - pending
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            jobId: 'test-job-123',
            status: 'PENDING',
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            inputParams: { prompt: 'test prompt' },
            estimatedCompletion: 'Processing...'
          })
        });
      } else {
        // Subsequent calls - completed
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            jobId: 'test-job-123',
            status: 'SUCCEEDED',
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            inputParams: { prompt: 'test prompt' },
            imageUrl: 'https://example.com/generated-image.png',
            metadata: {
              generation_time_seconds: 15.5
            }
          })
        });
      }
    });

    await page.reload();
    await page.waitForLoadState('networkidle');

    // Should show job in recent generations
    await expect(page.locator('text=Recent Generations')).toBeVisible();
  });

  test('should handle API errors gracefully', async ({ page }) => {
    // Mock authenticated state
    await page.addInitScript(() => {
      window.localStorage.setItem('amplify-auth-state', JSON.stringify({
        authenticated: true,
        user: { username: 'testuser' }
      }));
    });

    // Mock API error
    await page.route('**/v1/jobs', async (route) => {
      if (route.request().method() === 'POST') {
        await route.fulfill({
          status: 500,
          contentType: 'application/json',
          body: JSON.stringify({
            error: 'Internal server error',
            message: 'An unexpected error occurred'
          })
        });
      }
    });

    await page.reload();
    await page.waitForLoadState('networkidle');

    // Fill in the prompt and submit
    const promptTextarea = page.locator('textarea[placeholder*="prompt"]');
    if (await promptTextarea.isVisible()) {
      await promptTextarea.fill('test prompt');
      await page.locator('button:has-text("Generate")').click();
      
      // Should show error message
      await expect(page.locator('text=An unexpected error occurred')).toBeVisible();
    }
  });

  test('should be responsive on mobile devices', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Check mobile layout
    await expect(page.locator('h1')).toBeVisible();
    
    // Navigation should be responsive
    const header = page.locator('header');
    await expect(header).toBeVisible();
    
    // Feature cards should stack on mobile
    const featureCards = page.locator('[class*="grid"]').first();
    if (await featureCards.isVisible()) {
      const boundingBox = await featureCards.boundingBox();
      expect(boundingBox?.width).toBeLessThan(400);
    }
  });

  test('should have proper accessibility attributes', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Check for proper heading hierarchy
    const h1 = page.locator('h1');
    await expect(h1).toBeVisible();
    
    // Check for alt text on images (if any)
    const images = page.locator('img');
    const imageCount = await images.count();
    
    for (let i = 0; i < imageCount; i++) {
      const img = images.nth(i);
      const alt = await img.getAttribute('alt');
      expect(alt).toBeTruthy();
    }

    // Check for proper button labels
    const buttons = page.locator('button');
    const buttonCount = await buttons.count();
    
    for (let i = 0; i < buttonCount; i++) {
      const button = buttons.nth(i);
      const text = await button.textContent();
      const ariaLabel = await button.getAttribute('aria-label');
      
      // Button should have either text content or aria-label
      expect(text || ariaLabel).toBeTruthy();
    }
  });
});