<?php
declare(strict_types=1);

require_once __DIR__ . '/position_functions.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function respond(int $status, array $body): never
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(405, ['ok' => false, 'error' => 'Method not allowed.']);
}

$configuredKey = getenv('POSITION_API_KEY') ?: '';
$providedKey = $_SERVER['HTTP_X_POSITION_KEY'] ?? '';
if ($configuredKey === '' || !hash_equals($configuredKey, $providedKey)) {
    respond(401, ['ok' => false, 'error' => 'Unauthorized.']);
}

$rawBody = file_get_contents('php://input');
$payload = json_decode($rawBody ?: '', true);
if (!is_array($payload)) {
    respond(400, ['ok' => false, 'error' => 'A valid JSON request body is required.']);
}

try {
    $pdo = positionDatabase();
    $results = calculateClassPositions($pdo, $payload);
    respond(200, [
        'ok' => true,
        'count' => count($results),
        'results' => $results,
    ]);
} catch (InvalidArgumentException $error) {
    respond(422, ['ok' => false, 'error' => $error->getMessage()]);
} catch (Throwable $error) {
    error_log($error->getMessage());
    respond(500, ['ok' => false, 'error' => 'Position calculation failed.']);
}

