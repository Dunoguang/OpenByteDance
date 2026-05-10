import argparse
import os
import sys

import uvicorn

from app.logger import logger
from app.server import app
import asyncio
import time


# from app.tools.browser.browser_manager import set_request_timeout

async def pre_create_default_kernel():
    """初始化默认kernel"""
    try:
        from app.code_interpreter import get_or_init_kernel
        await get_or_init_kernel("defaultCIKernel", True, "/mnt")
        logger.info("Default kernel pre-created successfully")
    except Exception as e:
        logger.error(f"Failed to pre-create default kernel: {e}")


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Start the terminal and browser proxy server")
    
    parser.add_argument(
        "--port", 
        type=int, 
        default=8080, 
        help="Port to run the server on (default: 8080)"
    )
    
    parser.add_argument(
        "--host",
        type=str,
        default="0.0.0.0",
        help="Host interface to bind to (default: 0.0.0.0)"
    )
    
    parser.add_argument(
        "--log-level",
        type=str,
        choices=["debug", "info", "warning", "error", "critical"],
        default="info",
        help="Logging level (default: info)"
    )
    
    parser.add_argument(
        "--chrome-path",
        type=str,
        default=None,
        help="Path to Chrome browser instance"
    )

    parser.add_argument(
        "--headless",
        action="store_true",
        help="Whether to run the browser in headless mode (default: False)"
    )

    parser.add_argument(
        "--request-timeout",
        type=int,
        default=None,
        help="Timeout for requests to the browser in seconds (default: 60)"
    )

    parser.add_argument(
        "--proxy-server",
        type=str,
        default=None,
        help="Proxy server to use for requests to the browser (default: None)"
    )

    parser.add_argument(
        "--proxy-username",
        type=str,
        default=None,
        help="Proxy username to use for requests to the browser (default: None)"
    )

    parser.add_argument(
        "--proxy-password",
        type=str,
        default=None,
        help="Proxy password to use for requests to the browser (default: None)"
    )
    
    return parser.parse_args()


async def async_main():
    # 在开始时创建后台任务
    init_kernel_task = asyncio.create_task(pre_create_default_kernel())
    logger.info("Kernel preload started in background...")
    # Parse command-line arguments
    args = parse_args()
    from app.logger import set_log_level
    set_log_level('DEBUG')
    # set_log_level(args.log_level)

    # Set Chrome instance path if provided
    if args.chrome_path:
        os.environ['CHROME_INSTANCE_PATH'] = args.chrome_path

    if args.headless:
        os.environ['CHROME_HEADLESS'] = "True"

    if args.proxy_server:
        os.environ['PROXY_SERVER'] = args.proxy_server

    if args.proxy_username:
        os.environ['PROXY_USERNAME'] = args.proxy_username

    if args.proxy_password:
        os.environ['PROXY_PASSWORD'] = args.proxy_password

    request_timeout = args.request_timeout
    if request_timeout is None:
        request_timeout = int(os.getenv('REQUEST_TIMEOUT', '60'))

    # set_request_timeout(request_timeout)
        
    # Log startup information
    logger.info(f"Starting server on {args.host}:{args.port}")
    logger.info(f"CHROME_INSTANCE_PATH env is {os.getenv('CHROME_INSTANCE_PATH', 'empty')}")
    logger.info(f"CHROME_HEADLESS env is {os.getenv('CHROME_HEADLESS', 'False')}")
    logger.info(f"PROXY_SERVER env is {os.getenv('PROXY_SERVER', 'empty')}")
    logger.info(f"request_timeout is {request_timeout}s")
    
    await init_kernel_task
    # Start the server
    config = uvicorn.Config(
        app=app,
        host=args.host,
        port=args.port,
        log_level=args.log_level
    )
    server = uvicorn.Server(config)
    await server.serve()


if __name__ == '__main__':
    try:
        asyncio.run(async_main())
    except Exception as e:
        logger.critical(f"Failed to start server: {e}")
        sys.exit(1)