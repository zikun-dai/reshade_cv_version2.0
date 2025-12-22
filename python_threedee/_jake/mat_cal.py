import numpy as np
from typing import Sequence

#TODO:


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



def check_rotation_matrix() -> None:
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

def main() -> None:
    M_UE_to_CV = np.array([
        [0, 1,  0],
        [0, 0, -1],
        [1, 0,  0]
    ])
    M_UE_to_CV_T = np.array([
        [0, 0, 1],
        [1, 0, 0],
        [0,-1, 0]
    ])
    mat = np.array([
        [0, 11, 21],
        [1, 12, 22],
        [2, 13, 23]
    ])
    # 计算 M_UE_to_CV @ mat @ M_UE_to_CV_T
    result = M_UE_to_CV @ mat
    print(result)

if __name__ == "__main__":
    main()
