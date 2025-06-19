.PHONY: sync install test clean

sync:
	uv sync --all-packages --dev

install:
	uv pip install -r requirements.txt

test:
	uv run pytest

