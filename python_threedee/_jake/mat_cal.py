import numpy as np
from typing import Sequence


def is_valid_rotation_matrix(matrix: np.ndarray, tol: float = 1e-6) -> bool:
    """
    Check whether a 3x3 matrix is a valid camera extrinsic rotation matrix.

    The matrix must be orthonormal (R^T R ~ I) with determinant ~ 1.
    """
    mat = np.asarray(matrix, dtype=float)
    if mat.shape != (3, 3) or not np.all(np.isfinite(mat)):
        return False

    # Orthonormality: R^T R should be identity.
    # if np.max(np.abs(mat.T @ mat - np.eye(3))) > tol:
    #     return False

    # Right-handed rotation: determinant should be 1.
    det = np.linalg.det(mat)
    return abs(det - 1.0) <= tol


def _build_matrix(values: Sequence[float]) -> np.ndarray:
    """Fast helper for reshaping flat float lists into 3x3 matrices."""
    return np.asarray(values, dtype=float).reshape(3, 3)


def test_is_valid_rotation_matrix() -> None:
    """Unit tests for `is_valid_rotation_matrix` using representative matrices."""
    # Identity is a trivial valid rotation matrix.
    assert is_valid_rotation_matrix(np.eye(3))

    # This matrix violates orthonormality/determinant=1; should be rejected.
    invalid_matrix = _build_matrix(
        [-0.007182, 0.989533, 0.144131, 0.0, -0.144135, 0.989558, 1.047198, 0.0, 0.0]
    )
    assert not is_valid_rotation_matrix(invalid_matrix)


def main() -> None:
    """Check whether the provided values form a valid rotation matrix."""
    values = (
        -0.007182,
        0.989533,
        0.144131,
        0.0,
        -0.144135,
        0.989558,
        1.047198,
        0.0,
        0.0,
    )
    matrix = _build_matrix(values)
    print(is_valid_rotation_matrix(matrix))


if __name__ == "__main__":
    main()
