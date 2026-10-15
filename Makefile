.PHONY: all install test benchmark demo clean lint

all: install test benchmark

install:
	python -m pip install --upgrade pip
	pip install -r requirements.txt
	pip install -e .

test:
	python -m pytest tests/ -v

benchmark:
	python tests/benchmark.py

demo:
	python src/interface.py

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.parquet" -delete

lint:
	python -m py_compile src/**/*.py tests/**/*.py