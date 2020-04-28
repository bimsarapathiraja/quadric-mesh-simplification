import numpy as np
cimport numpy as np

DTYPE_DOUBLE = np.double

ctypedef np.double_t DTYPE_DOUBLE_T

from preserve_bounds cimport preserve_bounds
from q cimport compute_Q
from targets cimport compute_targets, calculate_pair_attributes
from valid_pairs cimport compute_valid_pairs
from utils cimport get_rows

def simplify_mesh(positions, face, num_nodes, features=None, threshold=0.):
    r"""simplify a mesh by contracting edges using the algortihm from `"Surface Simplification Using Quadric Error Metrics"
    <http://mgarland.org/files/papers/quadrics.pdf>`_.

    Args:
        positions (:class:`ndarray`): array of shape num_nodes x 3 containing the x, y, z position for each node
        face (:class:`ndarray`): array of shape num_faces x 3 containing the indices for each triangular face
        num_nodes (number): number of nodes that the final mesh will have
        threshold (number, optional): threshold of vertices distance to be a valid pair

    :rtype: (:class:`ndarray`, :class:`ndarray`)
    """

    # 1. compute Q for all vertices
    cdef np.ndarray Q = compute_Q(positions, face)

    # add penalty for boundaries
    preserve_bounds(positions, face, Q)

    # 2. Select valid pairs
    cdef np.ndarray valid_pairs = compute_valid_pairs(positions, face, threshold)

    # 3. compute optimal contration targets
    # of shape err, v1, v2, target, (features)
    cdef np.ndarray pairs
    
    pairs = compute_targets(positions, Q, valid_pairs, features)

    # 4. create head sorted by costs
    pairs = sort_by_error(pairs)
    print(pairs[:, 1:3])

    # 5. contract vertices until num_nodes reached
    cdef double error
    cdef long v1
    cdef long v2
    cdef np.ndarray p, rows, cols, row, rows_v1, rows_v2

    cdef int target_offset = 3
    cdef int feature_offset = 3 + 3
    cdef long i
    while (
            get_rows(positions != -np.inf).shape[0] > num_nodes and
            pairs.shape[0] > 0
        ):

        p = pairs[0]
        v1 = p[1]
        v2 = p[2]

        # update positions
        positions[v1] = np.copy(p[target_offset:feature_offset])
        #positions = np.delete(positions, v2, 0)
        mark_row_for_del(positions, v2)

        # update Q
        Q[v1] = Q[v1] + Q[v2]
        #positions = np.delete(Q, v2, 0)
        mark_row_for_del(Q, v2)

        # update features
        if features is not None and p:
            features[v1] = p[feature_offset:]
            #features = np.delete(features, v2, 0)
            mark_row_for_del(features, v2)

        # remove p
        pairs = np.delete(pairs, 0, 0)

        
        # update all other valid pairs

        # set all v2 to v1 since it doesnt exists anymore and was replaced by the 
        # new target
        rows, cols = np.where(pairs[:, 1:3] == v2)
        pairs[rows, cols + 1] = v1

        # update all rows with indexes of v1
        rows = get_rows(pairs[:, 1:3] == v1)
        for i in rows:
            p = pairs[i]
            if p[1] == v1:
                pairs[i] = calculate_pair_attributes(v1, p[2], positions, Q, features)
            elif p[2] == v1:
                pairs[i] = calculate_pair_attributes(p[1], v1, positions, Q, features)

        # sort by errors
        pairs = sort_by_error(pairs)

        # update face from new pairs
        rows_v1 = get_rows(face == v1)
        rows_v2 = get_rows(face == v2)
        for i in rows_v1:
            # option 1: remove faces with both nodes of pair
            if (rows_v2 == i).any():
                mark_row_for_del(face, i)

        # option 2: point faces to new merged node
        face[face == v2] = v1

        # update indexes for all vertices
        face[face > v2] -= - 1

    positions = delete_marked_rows(positions)
    face = delete_marked_rows(face)

    if features is not None:
        features = delete_marked_rows(features)
        return positions, face, features
    else:
        return positions, face

cdef np.ndarray sort_by_error(np.ndarray pairs):
    cdef view = ', '.join(['double' for _ in range(pairs.shape[1])])
    
    if pairs.shape[0] > 0:
        pairs.view(view).sort(order=['f0'], axis=0)
        return np.unique(pairs, axis=0)
    else:
        return pairs

cdef void mark_row_for_del(np.ndarray arr, long row):
    arr[row] = np.ones((arr.shape[1])) * (np.NINF)

cdef np.ndarray delete_marked_rows(np.ndarray arr):
    cdef np.ndarray rows
    if arr.dtype == 'int64':
        rows = get_rows(arr < 0)
    else:
        rows = get_rows(arr == np.NINF)
    return np.delete(arr, rows, axis=0)


