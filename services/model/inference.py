#!/usr/bin/env python3
"""
SageMaker Inference Handler for Stable Diffusion Image Generation
Supports both synchronous and asynchronous inference modes
"""

import json
import logging
import os
import sys
import time
import traceback
from io import BytesIO
from typing import Dict, Any, Optional, Tuple
import base64

import torch
import numpy as np
from PIL import Image
from diffusers import StableDiffusionXLPipeline, DPMSolverMultistepScheduler
from diffusers.utils import logging as diffusers_logging
import boto3
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Suppress diffusers warnings
diffusers_logging.set_verbosity_error()

class StableDiffusionInferenceHandler:
    """
    SageMaker inference handler for Stable Diffusion XL
    """
    
    def __init__(self):
        self.pipeline = None
        self.device = None
        self.model_loaded = False
        self.s3_client = boto3.client('s3')
        
        # Configuration
        self.model_id = os.environ.get('MODEL_ID', 'stabilityai/stable-diffusion-xl-base-1.0')
        self.model_cache_root = os.environ.get('MODEL_CACHE_ROOT', '/tmp/model_cache')
        self.max_width = int(os.environ.get('MAX_WIDTH', '1024'))
        self.max_height = int(os.environ.get('MAX_HEIGHT', '1024'))
        self.max_steps = int(os.environ.get('MAX_STEPS', '50'))
        self.default_steps = int(os.environ.get('DEFAULT_STEPS', '20'))
        
        # Create cache directories
        os.makedirs(self.model_cache_root, exist_ok=True)
        os.makedirs('/tmp/transformers_cache', exist_ok=True)
        os.makedirs('/tmp/huggingface_cache', exist_ok=True)
        
        logger.info(f"Initialized handler with model_id: {self.model_id}")
        logger.info(f"Cache directory: {self.model_cache_root}")
        logger.info(f"CUDA available: {torch.cuda.is_available()}")
        
        if torch.cuda.is_available():
            logger.info(f"GPU: {torch.cuda.get_device_name(0)}")
            logger.info(f"GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")
    
    def load_model(self) -> None:
        """Load the Stable Diffusion model"""
        if self.model_loaded:
            return
            
        logger.info("Loading Stable Diffusion XL model...")
        start_time = time.time()
        
        try:
            # Determine device
            if torch.cuda.is_available():
                self.device = "cuda"
                torch.cuda.empty_cache()
            else:
                self.device = "cpu"
                logger.warning("CUDA not available, using CPU (will be very slow)")
            
            logger.info(f"Using device: {self.device}")
            
            # Load pipeline
            self.pipeline = StableDiffusionXLPipeline.from_pretrained(
                self.model_id,
                torch_dtype=torch.float16 if self.device == "cuda" else torch.float32,
                use_safetensors=True,
                cache_dir=self.model_cache_root,
                local_files_only=False
            )
            
            # Move to device
            self.pipeline = self.pipeline.to(self.device)
            
            # Optimize for inference
            if self.device == "cuda":
                # Enable memory efficient attention
                self.pipeline.enable_attention_slicing()
                self.pipeline.enable_model_cpu_offload()
                
                # Use DPM++ scheduler for better quality/speed tradeoff
                self.pipeline.scheduler = DPMSolverMultistepScheduler.from_config(
                    self.pipeline.scheduler.config
                )
                
                # Compile model for faster inference (PyTorch 2.0+)
                try:
                    self.pipeline.unet = torch.compile(self.pipeline.unet, mode="reduce-overhead")
                    logger.info("Model compiled for faster inference")
                except Exception as e:
                    logger.warning(f"Could not compile model: {e}")
            
            # Warm up the pipeline
            logger.info("Warming up pipeline...")
            warmup_prompt = "a simple test image"
            _ = self.pipeline(
                warmup_prompt,
                num_inference_steps=1,
                width=512,
                height=512,
                guidance_scale=1.0
            )
            
            self.model_loaded = True
            load_time = time.time() - start_time
            logger.info(f"Model loaded successfully in {load_time:.2f} seconds")
            
            # Log memory usage
            if self.device == "cuda":
                memory_allocated = torch.cuda.memory_allocated() / 1024**3
                memory_reserved = torch.cuda.memory_reserved() / 1024**3
                logger.info(f"GPU Memory - Allocated: {memory_allocated:.2f} GB, Reserved: {memory_reserved:.2f} GB")
                
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            logger.error(traceback.format_exc())
            raise
    
    def validate_input(self, input_data: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
        """Validate and normalize input parameters"""
        
        # Extract prompt
        prompt = input_data.get('inputs', input_data.get('prompt', ''))
        if not prompt or not isinstance(prompt, str):
            raise ValueError("Missing or invalid 'inputs' or 'prompt' field")
        
        prompt = prompt.strip()
        if len(prompt) == 0:
            raise ValueError("Prompt cannot be empty")
        
        if len(prompt) > 1000:
            raise ValueError("Prompt too long (max 1000 characters)")
        
        # Extract parameters
        parameters = input_data.get('parameters', {})
        
        # Validate and set defaults
        params = {
            'num_inference_steps': min(max(parameters.get('num_inference_steps', self.default_steps), 1), self.max_steps),
            'guidance_scale': max(min(parameters.get('guidance_scale', 7.5), 20.0), 1.0),
            'width': min(max(parameters.get('width', 1024), 256), self.max_width),
            'height': min(max(parameters.get('height', 1024), 256), self.max_height),
            'seed': parameters.get('seed', None),
            'negative_prompt': parameters.get('negative_prompt', ''),
            'num_images_per_prompt': 1  # Always generate 1 image
        }
        
        # Ensure dimensions are multiples of 64
        params['width'] = (params['width'] // 64) * 64
        params['height'] = (params['height'] // 64) * 64
        
        # Set seed if provided
        if params['seed'] is not None:
            if not isinstance(params['seed'], int) or params['seed'] < 0:
                params['seed'] = None
        
        logger.info(f"Validated parameters: {params}")
        return prompt, params
    
    def generate_image(self, prompt: str, parameters: Dict[str, Any]) -> Tuple[Image.Image, Dict[str, Any]]:
        """Generate image using Stable Diffusion"""
        
        logger.info(f"Generating image with prompt: '{prompt[:100]}...' if len(prompt) > 100 else prompt")
        start_time = time.time()
        
        try:
            # Set random seed if provided
            generator = None
            if parameters['seed'] is not None:
                generator = torch.Generator(device=self.device).manual_seed(parameters['seed'])
                logger.info(f"Using seed: {parameters['seed']}")
            
            # Generate image
            with torch.inference_mode():
                result = self.pipeline(
                    prompt=prompt,
                    negative_prompt=parameters['negative_prompt'] if parameters['negative_prompt'] else None,
                    num_inference_steps=parameters['num_inference_steps'],
                    guidance_scale=parameters['guidance_scale'],
                    width=parameters['width'],
                    height=parameters['height'],
                    generator=generator,
                    num_images_per_prompt=parameters['num_images_per_prompt']
                )
            
            image = result.images[0]
            generation_time = time.time() - start_time
            
            # Prepare metadata
            metadata = {
                'prompt': prompt,
                'parameters': parameters,
                'generation_time_seconds': round(generation_time, 2),
                'model_id': self.model_id,
                'device': self.device,
                'timestamp': time.time()
            }
            
            logger.info(f"Image generated successfully in {generation_time:.2f} seconds")
            return image, metadata
            
        except Exception as e:
            logger.error(f"Error generating image: {e}")
            logger.error(traceback.format_exc())
            raise
    
    def save_image_to_s3(self, image: Image.Image, bucket: str, key: str) -> str:
        """Save image to S3 and return the S3 URI"""
        try:
            # Convert image to bytes
            img_buffer = BytesIO()
            image.save(img_buffer, format='PNG', optimize=True)
            img_buffer.seek(0)
            
            # Upload to S3
            self.s3_client.put_object(
                Bucket=bucket,
                Key=key,
                Body=img_buffer.getvalue(),
                ContentType='image/png',
                Metadata={
                    'generated-by': 'stable-diffusion-xl',
                    'timestamp': str(int(time.time()))
                }
            )
            
            s3_uri = f"s3://{bucket}/{key}"
            logger.info(f"Image saved to S3: {s3_uri}")
            return s3_uri
            
        except ClientError as e:
            logger.error(f"Failed to save image to S3: {e}")
            raise
    
    def process_request(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process inference request"""
        
        try:
            # Load model if not already loaded
            if not self.model_loaded:
                self.load_model()
            
            # Validate input
            prompt, parameters = self.validate_input(input_data)
            
            # Generate image
            image, metadata = self.generate_image(prompt, parameters)
            
            # For async inference, save to S3
            if os.environ.get('SAGEMAKER_INFERENCE_MODE') == 'async':
                # Extract S3 output location from environment
                output_location = os.environ.get('SAGEMAKER_OUTPUT_LOCATION', '')
                if output_location.startswith('s3://'):
                    # Parse S3 URI
                    s3_parts = output_location.replace('s3://', '').split('/', 1)
                    bucket = s3_parts[0]
                    prefix = s3_parts[1] if len(s3_parts) > 1 else ''
                    
                    # Save image
                    image_key = f"{prefix}/generated_image.png"
                    image_s3_uri = self.save_image_to_s3(image, bucket, image_key)
                    
                    # Save metadata
                    metadata_key = f"{prefix}/metadata.json"
                    metadata_json = json.dumps(metadata, indent=2)
                    self.s3_client.put_object(
                        Bucket=bucket,
                        Key=metadata_key,
                        Body=metadata_json,
                        ContentType='application/json'
                    )
                    
                    return {
                        'image_s3_uri': image_s3_uri,
                        'metadata_s3_uri': f"s3://{bucket}/{metadata_key}",
                        'metadata': metadata
                    }
            
            # For sync inference, return base64 encoded image
            img_buffer = BytesIO()
            image.save(img_buffer, format='PNG')
            img_base64 = base64.b64encode(img_buffer.getvalue()).decode('utf-8')
            
            return {
                'generated_image': img_base64,
                'metadata': metadata
            }
            
        except Exception as e:
            logger.error(f"Error processing request: {e}")
            logger.error(traceback.format_exc())
            raise

# Global handler instance
handler = StableDiffusionInferenceHandler()

def model_fn(model_dir: str) -> StableDiffusionInferenceHandler:
    """Load model for SageMaker"""
    logger.info(f"Loading model from directory: {model_dir}")
    handler.load_model()
    return handler

def input_fn(request_body: str, content_type: str = 'application/json') -> Dict[str, Any]:
    """Parse input data"""
    logger.info(f"Received request with content_type: {content_type}")
    
    if content_type == 'application/json':
        return json.loads(request_body)
    else:
        raise ValueError(f"Unsupported content type: {content_type}")

def predict_fn(input_data: Dict[str, Any], model: StableDiffusionInferenceHandler) -> Dict[str, Any]:
    """Run inference"""
    return model.process_request(input_data)

def output_fn(prediction: Dict[str, Any], accept: str = 'application/json') -> str:
    """Format output"""
    if accept == 'application/json':
        return json.dumps(prediction)
    else:
        raise ValueError(f"Unsupported accept type: {accept}")

# For direct execution (testing)
if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Test Stable Diffusion Inference')
    parser.add_argument('--prompt', type=str, required=True, help='Text prompt for image generation')
    parser.add_argument('--steps', type=int, default=20, help='Number of inference steps')
    parser.add_argument('--width', type=int, default=1024, help='Image width')
    parser.add_argument('--height', type=int, default=1024, help='Image height')
    parser.add_argument('--seed', type=int, help='Random seed')
    parser.add_argument('--output', type=str, default='test_output.png', help='Output file path')
    
    args = parser.parse_args()
    
    # Test the handler
    test_input = {
        'inputs': args.prompt,
        'parameters': {
            'num_inference_steps': args.steps,
            'width': args.width,
            'height': args.height,
            'seed': args.seed
        }
    }
    
    try:
        result = handler.process_request(test_input)
        
        if 'generated_image' in result:
            # Decode and save image
            img_data = base64.b64decode(result['generated_image'])
            with open(args.output, 'wb') as f:
                f.write(img_data)
            print(f"Image saved to {args.output}")
        
        print(f"Generation completed in {result['metadata']['generation_time_seconds']} seconds")
        
    except Exception as e:
        logger.error(f"Test failed: {e}")
        sys.exit(1)